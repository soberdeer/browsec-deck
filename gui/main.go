package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"crypto/sha256"
	"embed"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

const (
	projectVersion   = "1.0.0"
	productName      = "Browsec Deck " + projectVersion
	payloadRoot      = "browsec-deck-" + projectVersion
	systemRootName   = ".browsec-deck"
	officialIconHash = "111a51070cd8eb42216fb84ed08f40dfe84b121c9923d9cdbe42f7d5fc2cda0e"
)

//go:embed payload.tar.gz browsec-desktop.png
var embeddedPayload embed.FS

type progressDialog struct {
	qdbus string
	ref   []string
}

func findCommand(names ...string) string {
	for _, name := range names {
		if path, err := exec.LookPath(name); err == nil {
			return path
		}
	}
	return ""
}

func runKDialog(icon string, args ...string) (string, error) {
	kdialog := findCommand("kdialog")
	if kdialog == "" {
		return "", errors.New("kdialog is not installed")
	}

	base := []string{"--title", productName}
	if icon != "" {
		base = append(base, "--icon", icon)
	}
	cmd := exec.Command(kdialog, append(base, args...)...)
	output, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

func showError(icon, message, details string) {
	if details != "" {
		if _, err := runKDialog(icon, "--detailederror", message, details); err == nil {
			return
		}
	}
	_, _ = runKDialog(icon, "--error", message)
}

func showMessage(icon, message string) {
	_, _ = runKDialog(icon, "--msgbox", message)
}

func newProgress(icon, label string) *progressDialog {
	qdbus := findCommand("qdbus6", "qdbus-qt6", "qdbus", "qdbus-qt5")
	if qdbus == "" {
		return nil
	}
	ref, err := runKDialog(icon, "--progressbar", label, "100")
	if err != nil {
		return nil
	}
	fields := strings.Fields(ref)
	if len(fields) < 2 {
		return nil
	}
	p := &progressDialog{qdbus: qdbus, ref: fields[:2]}
	p.call("showCancelButton", "false")
	p.call("setAutoClose", "false")
	return p
}

func (p *progressDialog) call(args ...string) {
	if p == nil {
		return
	}
	all := append(append([]string{}, p.ref...), args...)
	_ = exec.Command(p.qdbus, all...).Run()
}

func (p *progressDialog) update(value int, label string) {
	if p == nil {
		return
	}
	p.call("Set", "", "value", strconv.Itoa(value))
	if label != "" {
		p.call("setLabelText", label)
	}
}

func (p *progressDialog) close() {
	if p != nil {
		p.call("close")
	}
}

func safeTarget(root, name string) (string, error) {
	clean := filepath.Clean(name)
	if filepath.IsAbs(clean) || clean == ".." ||
		strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("unsafe payload path: %s", name)
	}
	target := filepath.Join(root, clean)
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." ||
		strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("payload path escapes extraction directory: %s", name)
	}
	return target, nil
}

func systemRootFor(home string) (string, error) {
	cleanHome := filepath.Clean(home)
	if !filepath.IsAbs(cleanHome) || cleanHome == string(filepath.Separator) {
		return "", fmt.Errorf("unsafe home directory: %s", home)
	}
	homeParent, err := filepath.EvalSymlinks(filepath.Dir(cleanHome))
	if err != nil {
		return "", fmt.Errorf("cannot resolve the home partition: %w", err)
	}
	if !filepath.IsAbs(homeParent) ||
		homeParent == string(filepath.Separator) {
		return "", fmt.Errorf("unsafe home partition root: %s", homeParent)
	}
	return filepath.Join(homeParent, systemRootName), nil
}

func installBaseFor(home, username string) (string, error) {
	systemRoot, err := systemRootFor(home)
	if err != nil {
		return "", err
	}
	return filepath.Join(systemRoot, username), nil
}

func verifyRootControlledDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("%s is not a real directory", path)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != 0 {
		return fmt.Errorf("%s is not owned by root", path)
	}
	if info.Mode().Perm()&0o022 != 0 {
		return fmt.Errorf("%s is writable by group or other users", path)
	}
	return nil
}

func ensureRootControlledDirectory(path string, mode os.FileMode) error {
	if err := verifyRootControlledDirectory(filepath.Dir(path)); err != nil {
		return err
	}
	if err := os.Mkdir(path, mode); err != nil && !errors.Is(err, os.ErrExist) {
		return err
	}
	if err := verifyRootControlledDirectory(path); err != nil {
		return err
	}
	return os.Chmod(path, mode)
}

func extractPayload(destination string) error {
	file, err := embeddedPayload.Open("payload.tar.gz")
	if err != nil {
		return err
	}
	defer file.Close()

	gz, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}

		target, err := safeTarget(destination, header.Name)
		if err != nil {
			return err
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, os.FileMode(header.Mode)&0o777); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(
				target,
				os.O_CREATE|os.O_WRONLY|os.O_TRUNC,
				os.FileMode(header.Mode)&0o777,
			)
			if err != nil {
				return err
			}
			_, copyErr := io.Copy(out, tr)
			closeErr := out.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
		default:
			return fmt.Errorf("unsupported payload entry: %s", header.Name)
		}
	}
}

func verifyIcon(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	actual := fmt.Sprintf("%x", sha256.Sum256(data))
	if actual != officialIconHash {
		return fmt.Errorf("official Browsec icon hash mismatch: %s", actual)
	}
	return nil
}

func writeVerifiedIcon(directory string) (string, error) {
	data, err := embeddedPayload.ReadFile("browsec-desktop.png")
	if err != nil {
		return "", err
	}
	actual := fmt.Sprintf("%x", sha256.Sum256(data))
	if actual != officialIconHash {
		return "", fmt.Errorf("official Browsec icon hash mismatch: %s", actual)
	}
	path := filepath.Join(directory, "browsec-desktop.png")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", err
	}
	return path, nil
}

func writeLatestLog(home, content string) string {
	path := filepath.Join(home, ".cache", "browsec-deck-installer.log")
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		return ""
	}
	return path
}

func progressForLine(line string) (int, string) {
	switch {
	case strings.Contains(line, "Install location:"):
		return 10, "Preparing the home-partition installation..."
	case strings.Contains(line, "Extracting browsec-desktop"):
		return 25, "Extracting the verified Browsec package..."
	case strings.Contains(line, "Adding Steam Deck application profiles"):
		return 45, "Adding Steam Deck application profiles..."
	case strings.Contains(line, "Chromium sandbox"):
		return 65, "Applying secure application permissions..."
	case strings.Contains(line, "Polkit:"):
		return 85, "Configuring DNS authorization..."
	case strings.Contains(line, "has been installed"):
		return 95, "Finishing the installation..."
	default:
		return -1, ""
	}
}

func runPrivileged(p *progressDialog, action, targetUser string) (string, error) {
	pkexec := findCommand("pkexec")
	if pkexec == "" {
		return "", errors.New("pkexec is not installed")
	}
	// Keep the exact running inode alive across the authorization dialog. Using
	// the original path would allow a file in Downloads to be replaced before
	// pkexec opens it as root.
	self := fmt.Sprintf("/proc/%d/exe", os.Getpid())

	cmd := exec.Command(
		pkexec,
		self,
		"--privileged-action",
		action,
		"--target-user",
		targetUser,
	)
	pipeReader, pipeWriter := io.Pipe()
	cmd.Stdout = pipeWriter
	cmd.Stderr = pipeWriter

	var logBuilder strings.Builder
	var logMu sync.Mutex
	scanDone := make(chan struct{})
	go func() {
		defer close(scanDone)
		scanner := bufio.NewScanner(pipeReader)
		scanner.Buffer(make([]byte, 64*1024), 1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			logMu.Lock()
			logBuilder.WriteString(line)
			logBuilder.WriteByte('\n')
			logMu.Unlock()
			if value, label := progressForLine(line); value >= 0 {
				p.update(value, label)
			}
		}
	}()

	p.update(5, "Waiting for administrator authorization...")
	if err := cmd.Start(); err != nil {
		_ = pipeWriter.Close()
		<-scanDone
		return "", err
	}
	waitErr := cmd.Wait()
	_ = pipeWriter.Close()
	<-scanDone

	logMu.Lock()
	logText := logBuilder.String()
	logMu.Unlock()
	return logText, waitErr
}

func privilegedMain(args []string) int {
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "Error: privileged installer mode requires root.")
		return 2
	}
	if len(args) != 4 || args[0] != "--privileged-action" ||
		args[2] != "--target-user" {
		fmt.Fprintln(os.Stderr, "Error: invalid privileged installer arguments.")
		return 2
	}
	action := args[1]
	targetUser := args[3]
	if action != "install" && action != "repair" && action != "uninstall" {
		fmt.Fprintln(os.Stderr, "Error: invalid privileged installer action.")
		return 2
	}
	if !regexp.MustCompile(`^[a-z_][a-z0-9_-]*[$]?$`).MatchString(targetUser) ||
		targetUser == "root" {
		fmt.Fprintln(os.Stderr, "Error: invalid target user.")
		return 2
	}
	account, err := user.Lookup(targetUser)
	if err != nil || account.HomeDir == "" || !filepath.IsAbs(account.HomeDir) {
		fmt.Fprintln(os.Stderr, "Error: target user home directory was not found.")
		return 2
	}
	systemRoot, err := systemRootFor(account.HomeDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot locate the secure installation root: %v\n", err)
		return 2
	}
	if err := ensureRootControlledDirectory(systemRoot, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot secure the installation root: %v\n", err)
		return 2
	}
	tempRoot := filepath.Join(systemRoot, ".tmp")
	if err := ensureRootControlledDirectory(tempRoot, 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot secure the temporary root: %v\n", err)
		return 2
	}
	tempDir, err := os.MkdirTemp(tempRoot, "installer.")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot create root-owned temporary directory: %v\n", err)
		return 2
	}
	defer func() {
		_ = os.RemoveAll(tempDir)
		_ = os.Remove(tempRoot)
		_ = os.Remove(systemRoot)
	}()
	if err := os.Chmod(tempDir, 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot secure temporary directory: %v\n", err)
		return 2
	}
	if err := extractPayload(tempDir); err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot extract the verified installer payload: %v\n", err)
		return 2
	}

	kitRoot := filepath.Join(tempDir, payloadRoot)
	var command string
	var commandArgs []string
	switch action {
	case "install":
		command = filepath.Join(kitRoot, "install.sh")
		commandArgs = []string{"--user", targetUser}
	case "repair":
		command = filepath.Join(kitRoot, "templates", "repair-capability.sh")
		commandArgs = []string{"--user", targetUser}
	case "uninstall":
		command = filepath.Join(kitRoot, "uninstall.sh")
		commandArgs = []string{"--user", targetUser}
	}

	cmd := exec.Command("/usr/bin/bash", append([]string{command}, commandArgs...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return 1
	}
	return 0
}

func launchBrowsec(home, username string) error {
	installBase, err := installBaseFor(home, username)
	if err != nil {
		return err
	}
	launcher := filepath.Join(installBase, "launch.sh")
	if _, err := os.Stat(launcher); err != nil {
		return err
	}
	cmd := exec.Command(launcher)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Start()
}

func chooseAction(icon, home, username string) (string, error) {
	installBase, err := installBaseFor(home, username)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(installBase); err == nil {
		return runKDialog(
			icon,
			"--menu",
			productName+" is already installed. Choose an action:",
			"install",
			"Install or update",
			"repair",
			"Repair VPN permissions",
			"diagnose",
			"Run diagnostics",
			"uninstall",
			"Uninstall",
		)
	}
	legacyInstallBase := filepath.Join(home, ".local", "share", "browsec-deck-system")
	if _, err := os.Stat(legacyInstallBase); err == nil {
		return runKDialog(
			icon,
			"--menu",
			"An older Browsec Deck installation was found. Choose an action:",
			"install",
			"Install the secure update",
			"uninstall",
			"Uninstall",
		)
	}

	message := "<h2>Ready to install</h2>" +
		"<p>The VPN will be installed on the home partition. " +
		"No terminal or SteamOS read-only changes are required.</p>" +
		"<p>✓ Browsec Deck " + projectVersion + "<br>" +
		"✓ Steam, game, and application profiles<br>" +
		"✓ DNS setup without repeated password prompts<br>" +
		"✓ Installation on the home partition</p>" +
		"<p><small>One system administrator authorization will be required.</small></p>"
	_, err = runKDialog(
		icon,
		"--yesno",
		message,
		"--yes-label",
		"Install",
		"--no-label",
		"Cancel",
	)
	if err != nil {
		return "", err
	}
	return "install", nil
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--privileged-action" {
		os.Exit(privilegedMain(os.Args[1:]))
	}

	if runtime.GOOS != "linux" || runtime.GOARCH != "amd64" {
		showError("", "Browsec Deck Installer "+projectVersion+" requires 64-bit Linux/SteamOS.", "")
		return
	}
	if findCommand("kdialog") == "" {
		return
	}

	currentUser, err := user.Current()
	if err != nil || currentUser.Username == "" || currentUser.Username == "root" {
		showError("", "Run Browsec Deck Installer "+projectVersion+" from the regular Steam Deck desktop user.", "")
		return
	}
	home := currentUser.HomeDir
	cache, err := os.UserCacheDir()
	if err != nil {
		cache = filepath.Join(home, ".cache")
	}
	if err := os.MkdirAll(cache, 0o755); err != nil {
		showError("", "The user cache directory could not be created.", err.Error())
		return
	}

	workDir, err := os.MkdirTemp(cache, "browsec-deck-installer.")
	if err != nil {
		showError("", "A temporary installer directory could not be created.", err.Error())
		return
	}
	defer os.RemoveAll(workDir)

	icon, err := writeVerifiedIcon(workDir)
	if err != nil {
		showError("", "The official Browsec logo failed verification.", err.Error())
		return
	}

	action, err := chooseAction(icon, home, currentUser.Username)
	if err != nil || action == "" {
		return
	}

	if action == "diagnose" {
		installBase, pathErr := installBaseFor(home, currentUser.Username)
		if pathErr != nil {
			showError(icon, "The secure installation location could not be resolved.", pathErr.Error())
			return
		}
		diagnose := filepath.Join(installBase, "diagnose.sh")
		output, runErr := exec.Command("/usr/bin/bash", diagnose).CombinedOutput()
		logPath := writeLatestLog(home, string(output))
		if runErr != nil {
			showError(icon, "Diagnostics found one or more problems.", string(output))
			return
		}
		message := "Diagnostics completed successfully."
		if logPath != "" {
			message += "\n\nReport: " + logPath
		}
		showMessage(icon, message)
		return
	}

	progress := newProgress(icon, "Preparing "+productName+"...")
	switch action {
	case "install":
	case "repair":
	case "uninstall":
	default:
		progress.close()
		return
	}

	logText, runErr := runPrivileged(progress, action, currentUser.Username)
	logPath := writeLatestLog(home, logText)
	progress.update(100, "Complete")
	progress.close()

	if runErr != nil {
		message := "The operation did not complete."
		if strings.Contains(logText, "Browsec is still running") ||
			strings.Contains(logText, "VPN is still running") {
			message = "Disconnect the VPN and quit Browsec, then try again."
		}
		details := logText
		if logPath != "" {
			details += "\nInstaller log: " + logPath
		}
		showError(icon, message, details)
		return
	}

	switch action {
	case "install":
		_, launchErr := runKDialog(
			icon,
			"--yesno",
			"<h2>Installation complete</h2>"+
				"<p>"+productName+" is ready to use.</p>"+
				"<p>You can also launch it later from the KDE application menu.</p>",
			"--yes-label",
			"Launch Browsec",
			"--no-label",
			"Close",
		)
		if launchErr == nil {
			if err := launchBrowsec(home, currentUser.Username); err != nil {
				showError(icon, productName+" could not be launched.", err.Error())
			}
		}
	case "repair":
		showMessage(icon, "VPN permissions were repaired successfully.")
	case "uninstall":
		showMessage(icon, productName+" was uninstalled successfully.")
	}
}
