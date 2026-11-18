# Sourced by smoke.sh. End-to-end checks of Mr. Gym's main flows on the emulator.
# Some keyboards ignore ESC; fall back to Back while the keyboard is still showing.
hide_keyboard() {
  adb shell input keyevent 111; sleep 1
  if adb shell dumpsys input_method | grep -qE "mInputShown=true|isInputShown=true"; then adb shell input keyevent 4; sleep 1; fi
}
# Starts on Home after a relaunch.

clear_field() { for i in $(seq 1 14); do adb shell input keyevent 67; done; }
pin() { for d in $(echo "$1" | grep -o .); do tap_text "$d" >/dev/null; done; }

wait_for "Mark attendance" 20
expect "Check-ins today 0" 10 "dashboard starts with no check-ins"

# --- Add a member who has not paid yet -------------------------------------------------
tap_text "Members"; sleep 2
tap_text "Add member"; sleep 3
expect "Full name" 10 "add-member form opens"
tap_class EditText 0; type_text "Test Member"
tap_class EditText 1; type_text "03001234567"
hide_keyboard
scroll_to "First fee paid" >/dev/null
tap_contains "First fee paid"; sleep 1
expect "The fee will show as due" 5 "first-fee switch turns off"
tap_text "Save member"; sleep 3
expect "Test Member" 10 "new member is listed"
shot e2e-1-members
alive || fail "app died after adding a member"

# --- Dashboard sees the unpaid member ------------------------------------------------------
tap_text "Home"; sleep 3
expect "Due this week 1" 10 "dashboard counts the member as due"
expect "Revenue this month Rs 0" 5 "no revenue before a payment"
shot e2e-2-home-due

# --- Search ---------------------------------------------------------------------------------
tap_text "Members"; sleep 2
tap_class EditText 0; type_text "Test Mem"; hide_keyboard
expect "Test Member" 5 "search finds the member"
tap_class EditText 0; type_text "zzz"; hide_keyboard
expect "No member matches" 5 "search with no match shows an empty state"
expect_not "03001234567" 1 "non-matching member is hidden"
tap_class EditText 0; clear_field; type_text "0300123"; hide_keyboard
expect "Test Member" 5 "search by phone number finds the member"

# --- Member detail: attendance and payment ---------------------------------------------------
tap_text "Test Member"; sleep 3
expect "No payments recorded yet" 10 "member detail opens with no payments"
tap_text "Check in"; sleep 3
expect "Checked in today" 8 "attendance is marked"
tap_first "Record payment"; sleep 2
expect "Save payment" 8 "payment sheet opens"
shot e2e-3-payment-sheet
tap_text "Save payment"; sleep 3
expect "Payment saved" 5 "payment is saved"
expect_not "No payments recorded yet" 1 "payment shows in the log"
shot e2e-4-detail
back; sleep 1

# --- Dashboard counts update ----------------------------------------------------------------
tap_text "Home"; sleep 3
expect "Check-ins today 1" 10 "dashboard counts the check-in"
expect "Due this week 0" 5 "paid member no longer counts as due"
expect "Revenue this month Rs 3,000" 5 "revenue includes the payment"
shot e2e-5-home-paid

# --- Mark attendance from the front-desk screen ------------------------------------------------
tap_text "Mark attendance"; sleep 3
expect "1 checked in today" 8 "attendance screen shows today's count"
tap_contains "Test Member"; sleep 2
expect "already checked in today" 5 "a second check-in on the same day is refused"
back; sleep 1; back; sleep 1

# --- Everything persists after a relaunch --------------------------------------------------------
adb shell am force-stop "$PKG"; sleep 2
launch
wait_for "Mark attendance" 20
expect "Check-ins today 1" 10 "check-in persists after relaunch"
expect "Revenue this month Rs 3,000" 5 "payment persists after relaunch"
tap_text "Members"; sleep 2
expect "Test Member" 10 "member persists after relaunch"
tap_text "Test Member"; sleep 3
expect "Checked in today" 8 "attendance persists on the member"
expect_not "No payments recorded yet" 1 "payment log persists"
back; sleep 1

# --- Analytics shows the payment --------------------------------------------------------------
tap_text "Analytics"; sleep 3
expect "Collected this month Rs 3,000" 8 "analytics counts this month's revenue"
shot e2e-6-analytics

# --- Optional PIN lock ------------------------------------------------------------------------
tap_text "Settings"; sleep 2
scroll_to "App lock" >/dev/null
tap_text "App lock"; sleep 2
expect "Choose a PIN" 8 "PIN setup opens from Settings"
pin 1234; tap_text "Next"; sleep 2
expect "Confirm your PIN" 8 "PIN confirm step"
pin 1234; tap_text "Save PIN"; sleep 4
expect "A PIN is needed" 8 "app lock is on"
adb shell am force-stop "$PKG"; sleep 2
launch
expect "Enter PIN" 20 "lock screen appears after relaunch"
shot e2e-7-lock
pin 9999; tap_text "Unlock"; sleep 3
expect "Wrong PIN" 5 "wrong PIN is rejected"
pin 1234; tap_text "Unlock"; sleep 4
expect "Mark attendance" 10 "correct PIN unlocks"
tap_text "Settings"; sleep 2
scroll_to "App lock" >/dev/null
tap_text "App lock"; sleep 2
expect "Enter your current PIN" 8 "turning the lock off asks for the PIN"
pin 1234; tap_text "Continue"; sleep 4
expect "App lock is off" 6 "app lock turned off"
alive || fail "app died during the end-to-end tests"
