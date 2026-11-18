# Sourced by smoke.sh after the introduction: fill in the one-time gym setup.
# Some keyboards ignore ESC; fall back to Back while the keyboard is still showing.
hide_keyboard() {
  adb shell input keyevent 111; sleep 1
  if adb shell dumpsys input_method | grep -qE "mInputShown=true|isInputShown=true"; then adb shell input keyevent 4; sleep 1; fi
}
if wait_for "Set up your gym" 20; then
  tap_class EditText 0
  type_text "Iron Temple"
  tap_class EditText 2
  type_text "3000"
  adb shell input keyevent 66   # the fee field submits the form
  sleep 3
  if has_text "Set up your gym"; then hide_keyboard; tap_text "Continue"; sleep 3; fi
else
  echo "gym setup screen did not appear"
fi
