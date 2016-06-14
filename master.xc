/*
 * master.xc
 *
 *  Created on: 3 Jun 2016
 *      Author: Daniel
 */ 


#ifndef SYS_HEADERS
#define SYS_HEADERS
#include <xs1.h> //essential
#include <platform.h> //essential
#include <stdint.h> //variable types
#include <i2c.h> //i2c
#include <stdlib.h> //exiting
#include <syscall.h> //file operations
#include <stdio.h> //reading from console
#include <print.h> //writing to console and debugging
#include <timer.h> //delays
#include <math.h> //rounding
#endif

#include "xCFunctions.h" //function declarations
#include "AdafruitTranslation.h" //Adafruit_SI5351 i2c connection

//TRANSDUCER_COUNT is number of transducers per microcontroller
//DATA_LENGTH is the number of parameters
#ifndef TRANSDUCER_COUNT
#define TRANSDUCER_COUNT 8
#endif
#ifndef DATA_LENGTH
#define DATA_LENGTH 28
#endif

//HALF_WIDTH is half length waveperiod of push/pull (pp) in ticks
//PP_DELAY is many milliseconds pp is delayed by wrt pwm to precharge capacitors
//BUFFER_SIZE is input data buffer from parameters text file
//SOURCE is path to parameters text file
#define HALF_WIDTH 25
#define FULL_WIDTH (2*HALF_WIDTH)
#define PP_DELAY 6
#define BUFFER_SIZE 128
#define SOURCE "parameters.txt"

//4 4 bit ports for the pp output for 8 transducers (2 transducers per port)
out buffered port:4 pp[TRANSDUCER_COUNT/2] = {
        XS1_PORT_4A,
        XS1_PORT_4B,
        XS1_PORT_4C,
        XS1_PORT_4D
};
//8 1 bit ports for the pwm output for 8 transducers
out buffered port:1 pwm[TRANSDUCER_COUNT] = {
        XS1_PORT_1A,
        XS1_PORT_1B,
        XS1_PORT_1C,
        XS1_PORT_1D,
        XS1_PORT_1E,
        XS1_PORT_1L,
        XS1_PORT_1M,
        XS1_PORT_1N
};

//3 1 bit ports used to communicate to slave microcontrollers
out port goLine = XS1_PORT_1I;
out port restartLine = XS1_PORT_1J;
out port quitLine = XS1_PORT_1K;

//i2c 1 bit ports and reference clock signal from Adafruit Si5351
port p_scl = XS1_PORT_1F;
port p_sda = XS1_PORT_1G;
in port inClk = XS1_PORT_1H;

//reference clocks to drive outputs
clock ppClk = XS1_CLKBLK_1;
clock pwmClk = XS1_CLKBLK_2;


int main() {
    char yesNoMaybe = 0;
    ppStruct ppDatabase[TRANSDUCER_COUNT];
    pwmStruct pwmDatabase[TRANSDUCER_COUNT];
    i2c_master_if i2c[1];

    //configure output ports and reference clocks
    clkSet();

    while(1)
    {
        yesNoMaybe = 0;

        while(yesNoMaybe != 'y')
        {
            goLine <: 0;
            restartLine <: 0;
            quitLine <: 0;

            //import data from parameters text file and configure outputs
            dataProcessor(ppDatabase, pwmDatabase);

            par
            {
                i2c_master(i2c, 1, p_scl, p_sda, 400);
                adaSet(i2c[0], ppDatabase[0]);
            }

            //wait for user input
            printstr("Data recieved and processed! 'y' to commence "
                    "testing, 'r' to restart or 'q' to quit: ");
            yesNoMaybe = getchar();
            fflush(stdin);
            switch(yesNoMaybe)
            {
            case 'y':
                //tell slave microcontrollers to start outputs
                goLine <: 1;
                break;
            case 'r':
                //tell slave microcontrollers to restart file process
                restartLine <: 1;
                break;
            case 'q':
                //tell slave microcontrollers to quit
                quitLine <: 1;
                exit(0);
                break;
            }
        }

        //communication between pp and pwm
        streaming chan synchPulse[TRANSDUCER_COUNT];

        //begin test
        start_clock(ppClk);
        start_clock(pwmClk);
        par
        {
            //2 pwm outputs per core - 4 cores
            par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
                    {
                pwmDrive(pwmDatabase[2*i], pwmDatabase[(2*i) + 1],
                        pwm[2*i], pwm[(2*i) + 1], synchPulse[i]);
                    }
            //pp all run on seperate cores - 4 cores
            par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                freqDrive(ppDatabase[2*i], ppDatabase[(2*i) + 1], pp[i], synchPulse[i]);
            }
        }
    }
    return 0;
}


/*
 *      Links clocks to ports
 *
 *      - Set signal from Adafruit Si5351 as reference clock for pp
 *      - Set 100MHz clock as reference for pwm -> 2MHz at 50 tick wavelength
 */
void clkSet()
{
    configure_clock_src(ppClk, inClk);
    configure_clock_ref(pwmClk, 0);

    //link ports to clocks. Initial out = 0
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        configure_out_port(pp[i], ppClk, 0);
    }
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        configure_out_port(pwm[i], pwmClk, 0);
    }
}


/*
 *      Processes data from dataCapture
 *
 *      - Saves data to ppD and pwmD (sent by reference)
 *      - Adds pp delay to phase
 *      - Calculates pulseWait and burstWait
 *      - Adds phase to pwm output
 *      \param  ppD     struct to store pp parameters
 *      \param  pwmD    struct to store pwm parameters
 */
void dataProcessor(ppStruct ppD[TRANSDUCER_COUNT], pwmStruct pwmD[TRANSDUCER_COUNT])
{
    unsigned int data[DATA_LENGTH];

    //file reading
    dataCapture(data);

    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        ppD[i].frequency = data[0];
        ppD[i].testLength = data[1];
        ppD[i].burstLength = data[2];
        ppD[i].brf = data[3];
        ppD[i].pulseLength = data[4];
        ppD[i].prf = data[5];
        ppD[i].PLLmult = data[22];
        ppD[i].PLLnum = data[23];
        ppD[i].PLLdenom = data[24];
        ppD[i].multisynthDiv = data[25];
        ppD[i].multisynthNum = data[26];
        ppD[i].multisynthDenom = data[27];
    }
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {

        ppD[i].phase = data[i + 6];
        pwmD[i].magRatio = data[i + 14];
        if(pwmD[i].magRatio%2 != 0)
        {
            printstrln("magRatio must contain all even numbers. Exiting.");
            exit(1);
        }
    }

    //introduce PP_DELAY to every pp
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        ppD[i].phase = ppD[i].phase + (PP_DELAY*ppD[i].frequency/1000);
        ppD[i].burstWait = (FULL_WIDTH*ppD[i].frequency/ppD[i].brf) -
                (FULL_WIDTH*ppD[i].frequency*ppD[i].burstLength/ppD[i].prf);
        ppD[i].pulseWait = (FULL_WIDTH*ppD[i].frequency/ppD[i].prf) -
                (FULL_WIDTH*ppD[i].pulseLength);
    }
}


/*
 *      Imports data from parameters text file
 *
 *      \param  data    data array
 */
void dataCapture(unsigned int data[DATA_LENGTH])
{
    unsigned char readBuffer[BUFFER_SIZE];
    int fd;
    int flagCount = 0;
    unsigned int flags[BUFFER_SIZE];

    fd = _open(SOURCE, O_RDONLY, 0);
    if (fd == -1)
    {
        printstrln("Error: _open failed. Exiting.");
        exit(1);
    }
    _read(fd, readBuffer, BUFFER_SIZE);

    //flag every '.' in parameters text file
    for(size_t i = 0; i < BUFFER_SIZE; ++i)
    {
        if(readBuffer[i] == '.' && flagCount < DATA_LENGTH + 1)
        {
            flags[flagCount] = i;
            flagCount++;
        }
    }

    //convert string between '.' (parameters) from char to int
    for(size_t i = 0; i < DATA_LENGTH; ++i)
    {
        data[i] = 0;
    }
    for(size_t i = 0; i < DATA_LENGTH; ++i)
    {
        for(size_t j = flags[i]+1; j < flags[i+1]; ++j)
        {
            data[i] = data[i] * 10 + (readBuffer[j] - '0');
        }
        //printintln(data[i]); //debugging
    }

    if (_close(fd) != 0)
    {
        printstrln("Error: _close failed. Exiting.");
        exit(1);
    }
}


/*
 *      Communicate to and configure Adafruit Si5351A via i2c protocol in order
 *      to produce FULL_WIDTH*(pp frequency) clock. Output clock is equal to:
 *
 *      25MHz*(PLLmult + PLLnum/PLLdenom)/multisynthDiv
 *
 *      Use 0 for PLLnum and 1 for PLLdenom whenever possible for stability.
 *      PLLmult =           15 to 0b10010
 *      PLLnum =            0 to 1,048,575
 *      PLLdenom =          1 to 1,048,575
 *      multisynthDiv =     4, 6, 8 or 8 to 0b100100
 *
 *      Unknown complication below. If fixed, can utilise multisynthNum and
 *      multisynthDenom instead of 0 and 1:
 *      multisynthNum =     0 to 1,048,575
 *      multisynthDenom =   1 to 1,048,575
 *
 *      \param  i2c     i2c one-way communication interface
 *      \param  ppD     struct to store pp parameters
 */
void adaSet(client i2c_master_if i2c, ppStruct ppD) {
    Adafruit_SI5351 ada;
    Adafruit_SI5351Config(ada);
    if (begin(i2c, ada) != ERROR_NONE)
    {
        printstrln("Cannot connect to Adafruit SI5351. Exiting.");
        exit(1);
    }

    if(ppD.PLLnum == 0)
    {
        setupPLLInt(i2c, ada, SI5351_PLL_A, ppD.PLLmult);
    }
    else
    {
        setupPLL(i2c, ada, SI5351_PLL_A, ppD.PLLmult, ppD.PLLnum, ppD.PLLdenom);
    }
    //Has to have 0 and 1 as fractional components or this breaks and I don't know why
    setupMultisynth(i2c, ada, 0, SI5351_PLL_A, ppD.multisynthDiv, 0, 1);

    enableOutputs(i2c, ada, true);
    i2c.shutdown();
}


/*
 *      Drives 2 transducers' pwm outputs. Runs in parallel with other pwm and pp tasks
 *
 *      \param  pwmD1       pwm data for first transducer
 *      \param  pwmD2       pwm data for second transducer
 *      \param  p1          output port for first transducer
 *      \param  p2          output port for second transducer
 *      \param synchPulse   channel via which ppDrive signals pwmDrive
 *                          that test has ended
 */
void pwmDrive(pwmStruct pwmD1, pwmStruct pwmD2, out buffered port:1 p1,
        out buffered port:1 p2, streaming chanend synchPulse)
{
    int synch = 0;
    //current output values
    int currentDrive[4] = {1,1,0,0};
    unsigned int t1Rise, t2Rise, t1Fall, t2Fall;

    //t1 variables control first transducer, t2 controls second transducer
    //20 is arbitrarily added to minimise timing error
    if(pwmD1.magRatio > pwmD2.magRatio)
    {
        t1Rise = 21;
        t1Fall = 21 + pwmD1.magRatio;
        t2Rise = 20;
        t2Fall = 20 + pwmD2.magRatio;
    }
    else
    {
        t1Rise = 20;
        t1Fall = 20 + pwmD1.magRatio;
        t2Rise = 21;
        t2Fall = 21 + pwmD2.magRatio;
    }

    //saturated pwm detection (if pwm is 0 or FULL_WIDTH)
    if(pwmD1.magRatio == FULL_WIDTH)
    {
        currentDrive[0] = 1;
        currentDrive[2] = 1;
        pwmD1.magRatio = HALF_WIDTH;
    }
    else if(pwmD1.magRatio == 0)
    {
        currentDrive[0] = 0;
        currentDrive[2] = 0;
        pwmD1.magRatio = HALF_WIDTH;
    }

    if(pwmD2.magRatio == FULL_WIDTH)
    {
        currentDrive[1] = 1;
        currentDrive[3] = 1;
        pwmD2.magRatio = HALF_WIDTH;
    }
    else if(pwmD2.magRatio == 0)
    {
        currentDrive[1] = 0;
        currentDrive[3] = 0;
        pwmD2.magRatio = HALF_WIDTH;
    }

    //main drive loop. Returns if test ends
    if(t1Rise < t2Rise)
    {
        while(1)
        {
            select
            {
            case synchPulse :> synch:
                if(synch == 1)
                {
                    return;
                }
                break;
            default:
                p1 @ t1Rise <: currentDrive[0];
                p2 @ t2Rise <: currentDrive[1];
                p1 @ t1Fall <: currentDrive[2];
                p2 @ t2Fall <: currentDrive[3];
                t1Rise += FULL_WIDTH;
                t2Rise += FULL_WIDTH;
                t1Fall += FULL_WIDTH;
                t2Fall += FULL_WIDTH;
                break;
            }
        }
    }
    else
    {
        while(1)
        {
            select
            {
            case synchPulse :> synch:
                if(synch == 1)
                {
                    return;
                }
                break;
            default:
                p2 @ t2Rise <: currentDrive[1];
                p1 @ t1Rise <: currentDrive[0];
                p2 @ t2Fall <: currentDrive[3];
                p1 @ t1Fall <: currentDrive[2];
                t1Rise += FULL_WIDTH;
                t2Rise += FULL_WIDTH;
                t1Fall += FULL_WIDTH;
                t2Fall += FULL_WIDTH;
                break;
            }
        }
    }
}


/*
 *      Drives 2 transducers' pp outputs. Runs in parallel with other pwm and pp tasks
 *
 *      \param  ppD1        pp data for first transducer
 *      \param  ppD2        pp data for second transducer
 *      \param  p           4 bit output port for both transducers
 *      \param synchPulse   channel via which ppDrive signals pwmDrive
 *                          that test has ended
 */
void freqDrive(ppStruct ppD1, ppStruct ppD2, out buffered port:4 p, streaming chanend synchPulse)
{
    p <: 0b1111;
    //t1 controls the 2 LSB (first transducer) and t2 controls the 2 MSB (second transducer)
    unsigned int t1 = ppD1.phase;
    unsigned int t2 = ppD2.phase;

    signed int phaseDifference = t1 - t2;
    unsigned int currentDrive = 0b0101;
    synchPulse <: 0;

    //main drive loop. Returns if test ends
    for(size_t i=0; i < ppD1.testLength; ++i)
    {
        while(1) //debugging
            //for(size_t i = 0; i < ppD1.burstLength; ++i)
        {
            //if both transducers are of the same phase
            if(phaseDifference == 0)
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 0b1010; t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 0b0101; t1 += HALF_WIDTH;
                }
            }

            //if first transducer is 180 phase behind
            else if(phaseDifference == HALF_WIDTH)
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t2 <: currentDrive = 0b1001; t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 0b0110; t2 += HALF_WIDTH;
                }
            }

            //if second transducer is 180 phase behind
            else if(phaseDifference == -HALF_WIDTH)
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 0b0110; t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 0b1001; t1 += HALF_WIDTH;
                }
            }

            //non-special cases
            else if(abs(phaseDifference) < HALF_WIDTH)
            {
                if(t1 < t2)
                {
                    for(size_t i = 0; i < ppD1.pulseLength; ++i)
                    {
                        p @ t1 <: currentDrive = 0b0110;
                        p @ t2 <: currentDrive = 0b1010;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t1 <: currentDrive = 0b1001;
                        p @ t2 <: currentDrive = 0b0101;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                }
                else
                {
                    for(size_t i = 0; i < ppD1.pulseLength; ++i)
                    {
                        p @ t2 <: currentDrive = 0b1001;
                        p @ t1 <: currentDrive = 0b1010;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t2 <: currentDrive = 0b0110;
                        p @ t1 <: currentDrive = 0b0101;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                }
            }
            else //if(abs(phaseDifference) > HALF_WIDTH)
            {
                if(t1 < t2)
                {
                    p @ t1 <: currentDrive = 0b0110;
                    t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 0b0101;
                    t1 += HALF_WIDTH;
                    for(size_t i = 0; i < ppD1.pulseLength - 1; ++i)
                    {
                        p @ t2 <: currentDrive = 0b1001;
                        p @ t1 <: currentDrive = 0b1010;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t2 <: currentDrive = 0b0110;
                        p @ t1 <: currentDrive = 0b0101;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                    p @ t2 <: currentDrive = 0b1001;
                    t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 0b0101;
                    t2 += HALF_WIDTH;
                }
                else
                {
                    p @ t2 <: currentDrive = 0b1001;
                    t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 0b0101;
                    t2 += HALF_WIDTH;
                    for(size_t i = 0; i < ppD1.pulseLength - 1; ++i)
                    {
                        p @ t1 <: currentDrive = 0b0110;
                        p @ t2 <: currentDrive = 0b1010;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t1 <: currentDrive = 0b1001;
                        p @ t2 <: currentDrive = 0b0101;
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                    p @ t1 <: currentDrive = 0b0110;
                    t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 0b0101;
                    t1 += HALF_WIDTH;
                }
            }
            //wait before next pulse
            t1 += ppD1.pulseWait;
            t2 += ppD2.pulseWait;
        }
        //wait before next burst
        t1 += ppD1.burstWait;
        t2 += ppD2.burstWait;
    }
    //tell pwm to finish and return
    synchPulse <: 1;
    return;
}
