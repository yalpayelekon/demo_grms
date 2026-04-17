package main

import "testing"

func TestNormalizeServiceStates(t *testing.T) {
	tests := []struct {
		name       string
		dnd        string
		mur        string
		laundry    string
		wantDnd    string
		wantMur    string
		wantLnd    string
		wantChange bool
	}{
		{
			name:       "dnd canceled by mur requested",
			dnd:        "Yellow",
			mur:        "Requested",
			laundry:    "Off",
			wantDnd:    "Off",
			wantMur:    "Requested",
			wantLnd:    "Off",
			wantChange: true,
		},
		{
			name:       "dnd canceled by laundry requested",
			dnd:        "Yellow",
			mur:        "Off",
			laundry:    "Requested",
			wantDnd:    "Off",
			wantMur:    "Off",
			wantLnd:    "Requested",
			wantChange: true,
		},
		{
			name:       "mur and laundry can be requested together",
			dnd:        "Off",
			mur:        "Requested",
			laundry:    "Requested",
			wantDnd:    "Off",
			wantMur:    "Requested",
			wantLnd:    "Requested",
			wantChange: false,
		},
		{
			name:       "no change when no conflict",
			dnd:        "Off",
			mur:        "Finished",
			laundry:    "Finished",
			wantDnd:    "Off",
			wantMur:    "Finished",
			wantLnd:    "Finished",
			wantChange: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotDnd, gotMur, gotLnd, changed := normalizeServiceStates(
				tt.dnd,
				tt.mur,
				tt.laundry,
			)
			if gotDnd != tt.wantDnd || gotMur != tt.wantMur || gotLnd != tt.wantLnd || changed != tt.wantChange {
				t.Fatalf(
					"normalizeServiceStates(%q,%q,%q) got=(%q,%q,%q,%v) want=(%q,%q,%q,%v)",
					tt.dnd, tt.mur, tt.laundry,
					gotDnd, gotMur, gotLnd, changed,
					tt.wantDnd, tt.wantMur, tt.wantLnd, tt.wantChange,
				)
			}
		})
	}
}
