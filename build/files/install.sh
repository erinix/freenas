#!/bin/sh

. /.profile
__FREENAS_DEBUG__=1


get_product_name()
{
	local _product

	_product="FreeNAS"
	VAL="${_product}"

	export VAL
}

get_product_arch()
{
	local _arch

	_arch="amd64"
	VAL="${_arch}"

	export VAL
}

get_product_path()
{
	local _path

	_path=""
	VAL="${_path}"

	export VAL
}

get_image_name()
{
	local _product
	local _arch
	local _path

	get_product_name
	_product="${VAL}"

	get_product_arch
	_arch="${VAL}"

	get_product_path
	_path="${VAL}"

	VAL="${_path}/${_product}-${_arch}-embedded.gz"
	export VAL
}

build_config()
{
        # build_config ${_disk} ${_image}
        # ${_config_file} ${_os_size} ${_swap_size}

        local _disk=$1
        local _image=$2
        local _config_file=$3
        local _os_size=$4
        local _swap_size=$5

        cat << EOF > "${_config_file}"
# Added to stop pc-sysinstall from complaining
installMode=fresh
installInteractive=no
installType=FreeBSD
installMedium=dvd
packageType=tar

disk0=${_disk}
partition=image
image=/cdrom/FreeNAS-amd64-embedded.gz
bootManager=bsd
commitDiskPart
EOF
}

wait_keypress()
{
	local _tmp

	_msg=$1
	if [ -n "${_msg}" ]
	then
		echo "${_msg}"
	fi

	_msg="Press ENTER to continue."
	read -p "${_msg}" _tmp
}

get_memory_disks_list()
{
	local _disks

	VAL=""
	if [ -n "${__FREENAS_DEBUG__}" ]
	then
		_disks=`mdconfig -l`
		VAL="${_disks}"
	fi

	export VAL
}

get_physical_disks_list()
{
	local _disks
	local _list
	local _d

	_list=""
	_disks=`sysctl -n kern.disks`
	for _d in ${_disks}
	do
		if echo "${_d}" | grep -vE '^cd' >/dev/null 2>&1
		then
			_list="${_list}${_d} "
		fi
	done

	VAL="${_list}"
	export VAL
}

get_media_description()
{
	local _media

	_media=$1
	VAL=""

	if [ -n "${_media}" ]
	then
		_description=`pc-sysinstall disk-list -c |grep "^${_media}"\
			|awk -F':' '{print $2}'|sed -E 's|.*<(.*)>.*$|\1|'`
		VAL="${_description}"
	fi

	export VAL
}

disk_is_mounted()
{
	local _disk
	local _dev
	local _res

	_res=0
	_disk=$1
	_dev="/dev/${_disk}"
	mount -v|grep -E "^${_dev}[sp][0-9]+" >/dev/null 2>&1
	_res=$?

	return ${_res}
}

do_install()
{
	local _disklist
	local _tmpfile
	local _answer
	local _cdlist
	local _items
	local _cdrom
	local _disk
        local _image
        local _os_size
        local _swap_size
        local _config_file
	local _desc
	local _list
	local _msg
	local _i

        _tmpfile="/tmp/msg"

        cat << EOD > "${_tmpfile}"
FreeNAS  installer for Flash device or HDD.

WARNING: There will be some limitations:
1. This will erase ALL partitions and data on the destination disk
2. You can't use your destination disk for sharing data

Installing on USB key is the preferred way:
It saves you an IDE or SCSI channel for more hard drives.

EOD

    _msg=`cat "${_tmpfile}"`
    rm -f "${_tmpfile}"


    dialog --title "FreeNAS installation" --yesno "${_msg}" 17 74
    if [ "$?" != "0" ]
    then
        exit 1
    fi

    get_physical_disks_list
    _disklist="${VAL}"

    get_memory_disks_list
    _disklist="${_disklist} ${VAL}"	

    _list=""
    _items=0
    for _disk in ${_disklist}
    do
        get_media_description "${_disk}"
        _desc="${VAL}"
        _list="${_list} ${_disk} '${_desc}'"
        _items=$((${_items} + 1))
    done

    _tmpfile="/tmp/answer"
    eval "dialog --title 'Choose destination media' \
          --menu 'Select media where FreeNAS OS should be installed.' \
          15 60 ${_items} ${_list}" 2>"${_tmpfile}"
    if [ "$?" != "0" ]; then
        exit 1
    fi

    _disk=`cat "${_tmpfile}"`
    rm -f "${_tmpfile}"

    if disk_is_mounted "${_disk}" ; then
        wait_keypress "The destination drive is already in use!"
        exit 1
    fi

    get_image_name
    _image="${VAL}"

    _config_file="/tmp/pc-sysinstall.cfg"

    #  _cdrom, _disk, _image, _config_file
    # we can now build a config file for pc-sysinstall
    build_config  ${_disk} \
                  ${_image} ${_config_file} \
                  ${_os_size} ${_swap_size}

    # Run pc-sysinstall against the config generated
    ls /cdrom > /dev/null
    /rescue/pc-sysinstall -c ${_config_file}

    cat << EOD > "${_tmpfile}"

FreeNAS has been installed on ${_disk}.
You can now remove the CDROM and reboot the PC.
EOD

    _msg=`cat "${_tmpfile}"`
    rm -f "${_tmpfile}"

    wait_keypress "${_msg}"
    return 0
}

menu_null()
{
}

menu_reset()
{
}

menu_shell()
{
	eval /bin/sh
}

menu_reboot()
{
	dialog --yesno "Do you really want to reboot the system?" 5 46 no
	if [ "$?" = "0" ]
	then
		reboot >/dev/null
	fi
}

menu_shutdown()
{
	dialog --yesno "Do you really want to shutdown the system?" 5 46 no
	if [ "$?" = "0" ]
	then
		halt -p >/dev/null
	fi
}

menu_install()
{
	local _number
	local _tmpfile

	_tmpfile="/tmp/answer"

	dialog --clear --title "Install & Upgrade" --menu "" 12 73 6 \
	"1" "Install OS on HDD/Flash/USB" 2> "${_tmpfile}"

	if [ "$?" != "0" ]
	then
		return 1
	fi

	_number=`cat "${_tmpfile}"`
	case "${_number}" in
		1) do_install ;;
	esac

	return 0
}

menu_upgrade()
{
        # What we are really interested in doing here is preserving the
        # existing XML config file.
	local _number
	local _tmpfile

	_tmpfile="/tmp/answer"

	dialog --clear --title "Upgrade" --menu "" 12 73 6 \
	"1" "Upgrade and convert 'full' OS to 'embedded'" 2> "${_tmpfile}"

	if [ "$?" != "0" ]
	then
		return 1
	fi

	_number=`cat "${_tmpfile}"`
	case "${_number}" in
		1) do_upgrade_1 ;;
		2) ;;
		3) ;;
		4) ;;
		5) ;;
		6) ;;
	esac

	return 0
}


install_menu()
{
	while :
	do
		local _number

		echo " "
		echo " "
		echo "Console setup"
		echo "-------------"
		echo "1) Install/Upgrade to hard drive/flash device, etc."
		echo "2) Upgrade existing installation."
		echo "3) Shell"
		echo "4) Reboot system"
		echo "5) Shutdown System"
		echo " "

		read -p "Enter a number: " _number

		case "${_number}" in
			1) menu_install ;;
			2) menu_upgrade ;;
			3) menu_shell ;;
			4) menu_reboot ;;
			5) menu_shutdown ;;
		esac

	done
}

get_interface_list()
{
	local _ifaces

	_ifaces=`netstat -inW -f link | \
		tail +2 | \
		grep -Ev '^(ppp|sl|gif|faith|lo|vlan|tun|plip)' | \
		cut -f1 -d'*' | \
		awk '{ print $1 }'`

	VAL=""
	for i in ${_ifaces}
	do
		local _mac
		local _status
		local _up

		ifconfig "${i}" >/dev/null 2>&1
		if [ "$?" != "0" ]
		then
			continue
		fi

		_up="false"
		_mac=`ifconfig "${i}"|grep -E 'ether '|awk '{ print $2 }'`
		_status=`ifconfig "${i}"|grep status|awk '{ print $2 }'`
		if [ "${_status}" = "active" -o "${_status}" = "associated" ]
		then
			_up="true"
		fi

		if [ -n "${VAL}" ]
		then
			VAL="${VAL}|${i} ${_mac} ${_up}"
		else
			VAL="${i} ${_mac} ${_up}"
		fi

	done

	export VAL
}

autodetect_interface()
{
	local _ifname
	local _iflist_pre
	local _iflist_post
	local _tmpfile
	local _msg

	_ifname="${1}"

	get_interface_list;
	_iflist_pre="${VAL}"

	_tmpfile="/tmp/msg"
	cat << EOD > "${_tmpfile}"
Connect the ${_ifname} interface now and make
sure that the link is up.
Press OK to continue.
EOD
	_msg=`cat "${_tmpfile}"`
	rm -f "${_tmpfile}"

	dialog --clear --msgbox "${_msg}" 7 52

	get_interface_list;
	_iflist_post="${VAL}"

	for i in ${_iflist_pre}
	do
		local _iface_pre
		local _up_pre

		_iface_pre=`echo $i|awk '{ print $1 }'`
		_up_pre=`echo $i|awk '{ print $3 }'`

		for j in ${_iflist_post}
		do
			local _iface_post
			local _up_post

			_iface_post=`echo $j|awk '{ print $1 }'`
			_up_post=`echo $j|awk '{ print $3 }'`

			if [ "${_iface_pre}" = "${_iface_post}" \
				-a "${_up_post}" = "up" \
				-a "${_up_pre}" != "${_up_post}" ]
			then
				dialog --clear \
					--msgbox "Detected link-up on interface ${_iface_pre}" 5 44
				VAL="${_iface_pre}"
				export VAL

				return 0
			fi
		done
	done

	VAL=""
	export VAL

	dialog --clear --msgbox "No link-up detected." 5 24
	return 1
}

#
#	This should be broken up =-)
#
menu_setports()
{
	local _lanif
	local _iflist
	local _save_ifs
	local _tmpfile
	local _menulist
	local _msg

	#
	# Display detected interfaces
	#
	get_interface_list;
	_iflist="${VAL}"

	_tmpfile="/tmp/msg"
	cat << EOD > "${_tmpfile}"
If you don't know the names of your interfaces, you may use
auto-detection. In that case, disconnect all interfaces before you
begin, and reconnect each one when prompted to do so.
EOD
	_msg=`cat "${_tmpfile}"`
	rm -f "${_tmpfile}"

	_save_ifs="${IFS}"
	IFS="|"
	for i in ${_iflist}
	do
		local _iface
		local _mac
		local _up
		local _new

		_iface=`echo ${i}|awk '{ print $1 }'`
		_mac=`echo ${i}|awk '{ print $2 }'`
		_up=`echo ${i}|awk '{ print $3 }'`

		if [ "${_up}" = "true" ]
		then
			_new="${_iface} \"${_mac} (up)\""
		else
			_new="${_iface} ${_mac}"
		fi

		_menulist="${_menulist} ${_new}"

	done
	IFS="${_save_ifs}"

	_menulist="${_menulist} auto Auto-detection"

	_tmpfile="/tmp/answer"
	eval "dialog --clear  \
		--title \"Configure LAN interface\"  \
		--menu \"${_msg}\" \
		13 70 4 ${_menulist}" 2>"${_tmpfile}"
    if [ "$?" != "0" ]; then
		exit 1
    fi

    _lanif=`cat "${_tmpfile}"`
    rm -f "${_tmpfile}"

	if [ "${_lanif}" = "auto" ]
	then
		autodetect_interface "LAN"
		_lanif="${VAL}"
	fi

	
	#
	# Optional interfaces (XXX This needs testing XXX)
	#
	local _i1
	local _i
	local _loop
	local _opt

	_i=0
	_loop=1
	_opt="opt"
	_menulist="${_menulist} none \"Finish and exit configuration\""
	while [ "${_loop}" = "1" ]
	do
		local _tmp
		local _var
		local _val

		_tmp=$(eval "echo \$${_opt}${_i}")
		if [ -n "${_tmp}" ]
		then
			_i=`expr ${_i} + 1`
		fi

		_i1=`expr ${_i} + 1`

		_tmpfile="/tmp/msg"
		cat << EOD > "${_tmpfile}"
Select the optional OPT${_i1} interface name, auto-detection or none to
finish configuration.
EOD
		_msg=`cat "${_tmpfile}"`
		rm -f "${_tmpfile}"

		_tmpfile="/tmp/answer"
		eval "dialog --clear  \
			--title \"Configure OPT interface\"  \
			--menu \"${_msg}\" \
			13 70 5 ${_menulist}" 2>"${_tmpfile}"
    	if [ "$?" != "0" ]; then
			exit 1
    	fi

		eval "${_opt}${_i}=`cat ${_tmpfile}`"
    	rm -f "${_tmpfile}"

		_var=\$$(eval "echo ${_opt}${_i}")
		_val=$(eval "echo $_var")

		if [ -n "${_val}" ]
		then
			if [ "${_val}" = "auto" ]
			then
				local _ad

				autodetect_interface "optional OPT${_i1}"
				_ad="${VAL}"

				if [ -n "${_ad}" ]
				then
					eval "${_opt}${_i}=${_ad}"
				else
					unset `echo "${_opt}${_i}"`
				fi
				
			elif [ "${_val}" = "none" ]
			then
				unset `echo "${_opt}${_i}"`
				_loop=0
			fi
		fi
	done

	#
	# Build up OPT list
	#
	local _count
	local _ifoptlist

	_count="${_i}"
	_i=0

	while [ "${_i}" -lt "${_count}" ]
	do
		local _var
		local _val

		_var=\$$(eval "echo ${_opt}${_i}")
		_val=$(eval "echo $_var")

		if [ -n "${_val}" ]
		then
			_ifoptlist="${_ifoptlist} ${_val}"
		fi

		_i=`expr "${_i}" + 1`
	done


	#
	# Check for duplicate assignments
	#
	local _ifall
	local _files

	_i=0
	_ifall="${_lanif}"
	while [ "${_i}" -lt "${_count}" ]
	do
		local _var
		local _val

		_var=\$$(eval "echo ${_opt}${_i}")
		_val=$(eval "echo $_var")
		_ifall="${_ifall} ${_val}"

		_i=`expr "${_i}" + 1`
	done

	for i in ${_ifall}
	do
		local _file

		_file="/tmp/.${i}"
		if [ -f "${_file}" ]
		then
			dialog --clear --title "Error" \
				--msgbox "You can't assign the same interface twice!" 5 46
			rm ${_files}
			exit 1
		fi

		touch "${_file}"
		_files="${_files} ${_file}"
	done

	rm ${_files}


	#
	# ...
	#
	_tmpfile="/tmp/msg"
	cat << EOD > "${_tmpfile}"
The interfaces will be assigned as follows:

LAN  -> ${_lanif}

EOD
	_i=0
	for _ifopt in ${_ifoptlist}
	do
		local _n

		_n=`expr "${_i}" + 1`
		echo "OPT${_n} -> ${_ifopt}" >> "${_tmpfile}"
		_i=`expr "${_i}" + 1`
	done
	echo "\nDo you want to proceed?" >> "${_tmpfile}"
	_msg=`cat "${_tmpfile}"`
	rm -f "${_tmpfile}"

	dialog --clear --yesno "${_msg}" 100 47
    if [ "$?" != "0" ]
    then
		return 0
    fi

	#
	# Save config here....
	#

	return 0
}

config_menu()
{
	while :
	do
		local _number

		echo " "
		echo " "
		echo "Console setup"
		echo "-------------"
		echo "1) Assign interfaces"
		echo "2) Set LAP IP address"
		echo "3) Reset WebGUI password"
		echo "4) Reset to factory defaults"
		echo "5) Ping host"
		echo "6) Shell"
		echo "7) Reboot system"
		echo "8) Shutdown system"

		case "${PLATFORM}" in
			*-live[cC][dD])
				echo "9) Install/Upgrade to hard drive/flash device, etc." ;;
		esac

		echo " "

		read -p "Enter a number: " _number

		case "${_number}" in
			1) menu_setports ;;
			2) menu_setlanip ;;
			3) menu_password ;;
			4) menu_defaults ;;
			5) menu_ping ;;
			6) menu_shell ;;
			7) menu_reboot ;;
			8) menu_halt ;;
			9) install_menu ;;
		esac

	done
}


main()
{
	install_menu;
}


main;
