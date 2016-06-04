CONTENTS OF THIS FILE
---------------------
   
 * Introduction
 * Parameter text file format (IMPORTANT)
 * How to generate clock generator parameters (IMPORTANT)
 * How to run 1 microcontroller
 * How to run 32 microcontrollers
 * How to redistribute master binary
 * How to redistribute slave binaries
 * Other how tos


INTRODUCTION
------------
This README covers how to successfully start the Modular Ultrasound Transducer Array System (MUTAS) and redistribute .xe binaries (or executables) should there be a need to recompile said binaries.
The directory that contains this README will be referred to as root.

This README was made as a part of a third year group project by Daniel Ko.
This README was last updated on 16 June 2016.


PARAMETER TEXT FILE FORMAT
--------------------------
 * Must be saved as 'parameters.txt' in numbered folders in root (one for each micocontroller)
 * Must be in the form of:
.2000000.100.5.100.3.10000.40.40.40.40.40.40.40.40.0.0.0.0.0.0.0.0.20.0.1.8.0.1
 * From left to right:
  - frequency
  - testLength is the number of bursts in the test
  - burstLength is the number of pulses per burst
  - brf is the burst repetition frequency
  - pulseLength is the number of cycles per pulse
  - prf is the pulse repetition frequency (10000Hz max)
  - 8 values for magRatio which is the pwm 'on' period proportional to magnitude of push/pull (currently 0 to 50)
  - 8 values for phase of push/pull which is the number of ticks each transducer is delayed by (currently 0 to 49)
  - PLLmult is integer multiplication of 25MHz Adafruit clock generator (15 to 90)
  - PLLnum is numerator of fractional component of multiplication of 25MHz Adafruit clock generator (0 to 1,048,575)
  - PLLdenom is denominator of fractional component of multiplication of 25MHz Adafruit clock generator (1 to 1,048,575)
  - MultisynthDiv is integer division of PLL frequency (4 to 900)
  - MultisynthNum is numerator of fractional component of PLL frequency (0 to 1,048,575)
  - MultisynthDenom is denominator of fractional component of PLL frequency (1 to 1,048,575)
 * So clock generator frequency = (25*(PPLmult + PPLnum/PPLdenom))/(MultisynthDiv + MultisynthNum/MultisynthDenom)
 * CLOCK GENERATOR FREQUNCY MUST BE 50 TIMES THE REQUIRED TRANSDUCER FREQUENCY
 * THERE MUST BE NO SPACES IN THE TEXT FILE
 * FIRST AND LAST FULL STOPS (.) MUST BE INCLUDED


HOW TO GENERATE CLOCK GENERATOR PARAMETERS
------------------------------------------
 * Run 'Adafruit clockgen params.exe'
 * Enter desired TRANSDUCER FREQUENCY
 * A text file of parameters will be generated and saved as 'clkParams.txt' in root


HOW TO RUN 1 MICROCONTROLLER
----------------------------
Currently can control 8 transducers simultaneously
 * Connect the microcontroller to the computer via USB
 * Make sure an updated 'parameters.txt' file is in folder 1.
 * Run 'runMaster.bat'
 * Follow instructions on command window that opens


HOW TO RUN 32 MICROCONTROLLERS
------------------------------
Currently can control 256 transducers simultaneously
 * Connect the microcontrollers to the computer via USB
 * Make sure updated 'parameters.txt' file is in folder 1 through 32.
 * Run 'run32.bat'
 * Follow instructions on command window that STAYS open


HOW TO REDISTRIBUTE MASTER BINARY
---------------------------------
 * Recompile source code using command line or GUI
 * Locate recompiled binary (currently in 'XMOS_project_folder\bin')
 * Copy binary to folder 1 (RECOMMENDED: also copy to root)


HOW TO REDISTRIBUTE SLAVE BINARIES
----------------------------------
 * Recompile source code using command line or GUI
 * Locate recompiled binary (currently in 'XMOS_project_folder\bin')
 * Copy binary to root
 * Run 'moveSlaveBinaries.dat'


OTHER HOW TOS
-------------
 * mkdir32.bat makes 32 numbered folders in root if they do not already exist
 * mkdir32.bat contains a for loop that can be edited to create any number of numbered folders
 * run32.bat contains a for loop that can be edited to run any number of microcontrollers
