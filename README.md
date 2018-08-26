# Script information:
This script attempts to brute force an SFP's Vendor Password Using i2c-dev
The intended platform is a linux-based netowrk line card, used to unlock an SFP.
Once the SFP is unlocked, you can re-write the EEPROM to bypass vendor checks on generic optics

# Requirements
 1) i2c-dev (i2cget and i2cset)
 2) i2c EEPROM and password entry addresses / offsets. Will default to offset 0x7B if not specified. i2cget can help determine the correct address
