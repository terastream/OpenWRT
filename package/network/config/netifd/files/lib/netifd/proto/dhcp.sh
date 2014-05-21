#!/bin/sh

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_dhcp_init_config() {
	proto_config_add_string 'ipaddr:ipaddr'
	proto_config_add_string 'netmask:ipaddr'
	proto_config_add_string 'hostname:hostname'
	proto_config_add_string clientid
	proto_config_add_string vendorid
	proto_config_add_boolean 'broadcast:ipaddr'
	proto_config_add_string 'reqopts:list(string)'
	proto_config_add_string iface6rd
	proto_config_add_string sendopts
	proto_config_add_boolean delegate
	proto_config_add_string dhcp4o6if
}

proto_dhcp_setup() {
	local config="$1"
	local iface="$2"

	local ipaddr hostname clientid vendorid broadcast reqopts iface6rd sendopts delegate dhcp4o6if
	json_get_vars ipaddr hostname clientid vendorid broadcast reqopts iface6rd sendopts delegate dhcp4o6if

	local opt dhcpopts
	for opt in $reqopts; do
		append dhcpopts "-O $opt"
	done

	for opt in $sendopts; do
		append dhcpopts "-x $opt"
	done

    SERVERS=
    IPV6ADDRESS=
    if [ -n "dhcp4o6if" ]; then
        sleep 1
        json_load "$(ubus call network.interface."$dhcp4o6if" status)"
        json_select "dhcp4o6-servers"
        local Index="1"
        while json_get_type Status $Index; do
            json_get_var Status "$((Index++))"
            SERVERS="$Status"
        done
        SERVERS="--dhcp4o6 $SERVERS"
        json_select ".."

        # Get ipv6-address for CID
        json_load "$(ubus call network.interface."$dhcp4o6if" status)"
        json_select "ipv6-address"
        json_select 1
        json_get_var "ipv6_address" address
        json_select ".."
        json_select ".."
        IPV6ADDRESS="-I $ipv6_address"

        total_bits=0
        newaddress=
        for element in ${ipv6_address//:/ }; do
            nelement="$element"
            while [ ${#nelement} -ne 4 ]; do
                nelement="0$nelement"
            done
            if [ $total_bits -lt 14 ]; then
                newaddress="$newaddress$nelement"
            fi

            total_bits=$(($total_bits + ${#nelement}))
        done

        newaddress=$(echo "$newaddress" | cut -c1-14)
        client_id=
        counter=0
        while test -n "$newaddress"; do

            # Get the first character
            c=${newaddress:0:1}
            client_id="$client_id$c"

            # Trim the first character
            newaddress=${newaddress:1}
            counter=$(($counter + 1))
            if [ $((counter % 2)) -eq 0 ]; then
                client_id="$client_id:"
                counter=0
            fi

        done

        client_id=$(echo "$client_id" | cut -c1-20)
        client_id="-x 0x3d:$client_id"
    fi

	[ "$broadcast" = 1 ] && broadcast="-B" || broadcast=
	[ -n "$clientid" ] && clientid="-x 0x3d:${clientid//:/}" || clientid="-C"
	[ -n "$iface6rd" ] && proto_export "IFACE6RD=$iface6rd"
	[ "$delegate" = "0" ] && proto_export "IFACE6RD_DELEGATE=0"

	proto_export "INTERFACE=$config"
    proto_run_command "$config" udhcpc -R \
        -p /var/run/udhcpc-$iface.pid \
        -s /lib/netifd/dhcp.script \
        -f -t 0 -i "$iface" \
        $SERVERS $IPV6ADDRESS $client_id \
        ${ipaddr:+-r $ipaddr} \
        ${hostname:+-H $hostname} \
        ${vendorid:+-V $vendorid} \
        $clientid $broadcast $dhcpopts

}

proto_dhcp_teardown() {
	local interface="$1"
	proto_kill_command "$interface"
}

add_protocol dhcp

