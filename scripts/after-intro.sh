# Sourced by smoke.sh after the introduction: fill in the one-time gym setup.
if wait_for "Set up your gym" 20; then
  tap_class EditText 0
  type_text "Iron Temple"
  tap_class EditText 2
  type_text "3000"
  hide_keyboard
  tap_text "Continue"
  sleep 3
else
  echo "gym setup screen did not appear"
fi
