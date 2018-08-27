#! /bin/bash
#
#  Script information:
#    This script attempts to brute force an SFP's Vendor Password Using i2c-dev
#	 Intended platform is a CALIX EX line card to bypass GPON OIM vendor checks on generic optics
#    This script was not created by Calix, please do not contact them with issues!
#
#    Usage: -s 00:00:00:00 = starting string (optional, default 00:00:00:00)
#	 		-e 11:22:33:44 = ending string (optional, default FF:FF:FF:FF)
#			-b {i2c-bus number}
#			-a {i2c address}
#			-d {1st password address} (default = 7B)
#			-n {# of password bytes} default 4 (7B-7E)
#           -? Display usage instructions
#
#    i2c-dev does not support data addresses like a dedicated sfp brute-force board, so the i2c address is called directly.
#    If your SFP EEPROM (-p) is at i2c 0x50, then your SFP password entry (-a) should be at 0x51 (at the same addr. w/ the temp sensor data), run i2cdump on the address to verify.
#    Finding the SFP password entry offset and address is outside the scope of this utility. Refer to your SFP's data-sheet for info.
#
#    For Reference - GPON Port 1 is at i2c-2, 0x50. OIM password entry is at i2c-2, 0x51.

function usage {
printf "SFP Password Bruteforce V1
This script attempts to brute force an SFP's EEPROM password using i2c-dev. See script source for more info.
Usage: -b {i2c-bus number}
       -a {i2c p/w hex address, Ex: 0x51}
       -p {i2c EEPROM hex address, Ex: 0x50}
       -s 0x00000000 = first pw to guess (optional, default 0x00000000)
       -e 0x11223344 = last pw to guess (optional, default 0xFFFFFFFF)
       -d {1st password address} (optional, default = 7B)
       -n {number of password bytes} (optional, default = 4)
       -? Display usage instructions, but you already know that :)
"
    exit 1
}
if [[($@ == "--help") ||  ($@ == "-h")||  ($@ == "-?") || (${#@} == 0)]]
then
    usage
fi

#Set Up Vars
while [ "$1" != "" ]; do
    case $1 in
        -b )            shift
                        BUS=$1
                        ;;
        -a )            shift
                        I2CADDR=$1
                        ;;
        -s )            shift
                        INIT_PASS_LIT=$1
                        ;;
        -e )            shift
                        MAX_PASS_LIT=$1
                        ;;
        -d )            shift
                        DATA_START=$1
                        ;;
        -p )            shift
                        PROM_ADDR=$1
                        ;;
        -n )            shift
                        NUM_BYTES=$1
                        ;;
    esac
    shift
done
if [ "$BUS" = "" ]
then
    usage
fi
if [ "$I2CADDR" = "" ]
then
    usage
fi
if [ "$INIT_PASS_LIT" = "" ]
then
    INIT_PASS_LIT=0x00
fi
if [ "$PROM_ADDR" = "" ]
then
    usage
fi
if ! [[ "$NUM_BYTES" =~ ^[0-9]+$ ]]
then
    NUM_BYTES=4
fi
    let NB_TWOX=(${NUM_BYTES}*2)
    let NB_MULT=($NB_TWOX + 2)
if [ "$MAX_PASS_LIT" = "" ]
then
    MAX_PASS_LIT=0x"$(eval $(echo printf 'F%0.s' {1..$NB_TWOX}))"
fi
if [ "$DATA_START" = "" ]
then
    DATA_START=0x7B
fi

#Install the i2c-dev module. This might change depending on the platform
insmod /opt/calix/current/modules/ppc8544/i2c-dev.ko >/dev/null 2>&1

#Begin Brute Force. We will attempt to set the first MFR byte until it works. When it works, we will set it back to the original value and output the password.
#I'll consider manipulating this byte generally safe, because it's assumed the original brand is known, so the user can recover this byte manually if desired.
#This should be safer than writing the user space which may be already unlocked, or occupied with unknown data.
ORIG_MFR_BYTE="$(i2cget -y $BUS $PROM_ADDR 20)"

TEST="$(i2cset -y $BUS $PROM_ADDR 20 0x01 b 2>&1 >/dev/null | grep 'Warning')"

while [[ ${TEST} > 0 ]]
do

    j=0
    #We need individual bytes because this might not work with multiple bytes at once. The first number is at pos 3.
    for (( c = 3; c <= $NB_MULT; c+=2 )) do
        if [ "$c" == "3" ]
        then
            THIS_PASS_TO_BYTES=0x"$(printf %0${NB_TWOX}x $((${INIT_PASS_LIT})))"
        fi
        let j=($c+1)
        let k=($c-3)/2
        let DATA_ADDR=($DATA_START + $k)
        THIS_BYTE[c]=0x"$(echo ${THIS_PASS_TO_BYTES} | cut -c ${c}-${j})"
        i2cset -y $BUS $I2CADDR $DATA_ADDR "${THIS_BYTE[c]}" > /dev/null 2>&1
    done
    
    #testing with sending a block.
    #CALIX EX does not support this!
    # echo i2cset -y $BUS $I2CADDR $DATA_ADDR "${THIS_BYTE[*]} i"
    
    echo -ne "  SFP Bruteforce Running: ${THIS_BYTE[*]}"\\r

	if (( $INIT_PASS_LIT >= $MAX_PASS_LIT ))
	then
        #Failed - reset to original byte just in case.
        i2cset -y $BUS $PROM_ADDR 20 $ORIG_MFR_BYTE b >/dev/null 2>&1
        echo -en "\007"
        echo "
  ERROR: The password could not be found in the given range"
		exit 1;
	fi
	let INIT_PASS_LIT=($INIT_PASS_LIT + 1);
	
	#give the device time to process
	#sleep 0.015
done

#Found It
echo -en "\007"
echo "
DONE. The password is: ${THIS_BYTE[*]}"
i2cset -y $BUS $PROM_ADDR 20 $ORIG_MFR_BYTE b >/dev/null 2>&1
exit 0;
