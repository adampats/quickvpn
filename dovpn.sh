#!/bin/bash

# regions: nyc1, nyc2, nyc3, sfo1, sfo2, ams2, ams3, lon1, fra1, tor1, blr1
region='sfo2'
instance_size='1gb'
instance_image='ubuntu-14-04-x64'
timestamp=$(date +%Y-%m-%d-%H%M)
user_data_file='open-vpn.yml'
ssh_key_path="$HOME/.ssh/digitalocean-personal"
do_ssh_key_id='14681496'
ssh_timeout=300
tunnelblick_config_name='do-client'
tunnelblick_config_dir="$HOME/Library/Application Support/Tunnelblick/Configurations/"

echo -n "Checking for metadata file..."
if [[ ! -f $user_data_file ]]; then
	echo "not found... quit."
	exit 1
else
	echo "found."
fi

echo "Launching droplet in $region..."
droplet=$(doctl compute droplet create "vpn-$timestamp" --wait \
	--size "$instance_size" \
	--image "$instance_image" \
	--ssh-keys "$do_ssh_key_id" \
	--region "$region" \
	--user-data-file "$user_data_file" \
	--output json)

ip=$(echo "$droplet" | jq -r '.[]|.networks|.v4|.[]|.ip_address')

echo "Grabbing ovpn file..."
ovpn_file="do-client-$timestamp.ovpn"
if [[ -f $ovpn_file ]]; then
	mv -v $ovpn_file "$ovpn_file-old"
fi
state=1
ssh_time=0
while [[ $state -gt 0 ]]; do
	if [[ $ssh_time -lt $ssh_timeout ]]; then
		sleep 2
		scp -q -i $ssh_key_path \
			-o 'ConnectTimeout=2' \
			-o 'StrictHostKeyChecking=no' \
			-o 'LogLevel=QUIET' \
			root@$ip:/root/client.ovpn ./$ovpn_file 2>&1 >/dev/null | grep -i timeout
		if [[ -f $ovpn_file ]]; then
			state=0
		fi
		ssh_time=$((ssh_time+2))
		echo -n .
	else
		echo "SSH connection timeout reached... quit."
		exit 1
	fi
done
echo ""

echo "Inserting ovpn file to Tunnelblick directory..."
if [[ ! -d $tunnelblick_config_dir ]]; then
	echo "Tunnelblick not found!  Please download it or install via brew: "
	echo "https://www.tunnelblick.net/downloads.html"
	echo "brew install caskroom/cask/tunnelblick"
	echo "If you are using a different OpenVPN client, refer to ./do-client.ovpn ..."
else
	cp -v "./$ovpn_file" "$tunnelblick_config_dir/$tunnelblick_config_name.tlbk/" \
		"Contents/Resources/config.ovpn"
fi

echo "When finished, don't forget to kill the droplet with this command: "
destroy_cmd="doctl compute droplet delete vpn-$timestamp"
echo $destroy_cmd

echo "Done"
