# issues dynamic power budget on remote end
current_path=$(pwd)
configs_path="$current_path/../../../utils"
# Write 400W power budget
echo "Setting power budget to 400W"
$configs_path/set_power_budget.sh 400
sleep 120
# Write 360W power budget
echo "Setting power budget to 360W"
$configs_path/set_power_budget.sh 360
sleep 120
# Write 300W power budget
echo "Setting power budget to 300W"
$configs_path/set_power_budget.sh 300
sleep 120
# Write 400W power budget
echo "Setting power budget to 400W"
$configs_path/set_power_budget.sh 400
sleep 120
# Write 375W power budget
echo "Setting power budget to 375W"
$configs_path/set_power_budget.sh 375
sleep 120