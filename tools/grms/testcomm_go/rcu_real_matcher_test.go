package main

import "testing"

func TestMatcherFromRequestUsesCmdTypeAtByte3(t *testing.T) {
	msg := []byte{rcuHeader, 0x03, 0x00, 0x02, 0x05, 0x02}

	matcher := matcherFromRequest(msg, "request_reply")
	if matcher == nil {
		t.Fatal("matcherFromRequest returned nil")
	}
	if matcher.expectedCmdType == nil {
		t.Fatal("expectedCmdType is nil")
	}
	if *matcher.expectedCmdType != 2 {
		t.Fatalf("expectedCmdType=%d want=2", *matcher.expectedCmdType)
	}
	if *matcher.expectedCmdType == 3 {
		t.Fatalf("expectedCmdType=%d must not read length byte", *matcher.expectedCmdType)
	}
}
