package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSafeTargetRejectsEscapes(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"../escape", "/absolute", "sub/../../escape"} {
		if _, err := safeTarget(root, name); err == nil {
			t.Fatalf("safeTarget(%q) accepted an escaping path", name)
		}
	}
}

func TestSafeTargetAllowsContainedPath(t *testing.T) {
	root := t.TempDir()
	got, err := safeTarget(root, "kit/install.sh")
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(root, "kit", "install.sh")
	if got != want {
		t.Fatalf("safeTarget returned %q, want %q", got, want)
	}
}

func TestInstallBaseUsesHomePartitionParent(t *testing.T) {
	parent := t.TempDir()
	home := filepath.Join(parent, "deck")
	if err := os.Mkdir(home, 0o700); err != nil {
		t.Fatal(err)
	}

	got, err := installBaseFor(home, "deck")
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(parent, systemRootName, "deck")
	if got != want {
		t.Fatalf("installBaseFor returned %q, want %q", got, want)
	}
}
