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

#include <xCFunctions.h> //function declarations
#include <AdafruitTranslation.h> //Adafruit_SI5351 i2c connection

//preprocessor
//TRANSDUCER_COUNT is number of transducers per microcontroller
//REF_RATE is the reference clock rate at 100MHz
//HALF_WIDTH is half length waveperiod of push/pull (pp) in ticks
//PP_DELAY is many ticks much pp is delayed by. To precharge capacitors
//BUFFER_SIZE is input data buffer from parameters text file
//DATA_LENGTH is the number of parameters
//SOURCE is path to parameters text file
#ifndef TRANSDUCER_COUNT
#define TRANSDUCER_COUNT 8
#endif
#define REF_RATE 100000000
#define HALF_WIDTH 25
#define PP_DELAY 100//600000000 for normal operation
#define BUFFER_SIZE 128
#ifndef DATA_LENGTH
#define DATA_LENGTH 28
#endif
#define SOURCE "parameters.txt"

//port declarations


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
        XS1_PORT_1F,
        XS1_PORT_1G,
        XS1_PORT_1H
};

//3 1 bit ports used to communicate to slave microcontrollers
out port goLine = XS1_PORT_1I;
out port restartLine = XS1_PORT_1J;
out port quitLine = XS1_PORT_1K;

//i2c 1 bit ports and clk in
port p_scl = XS1_PORT_1L;
port p_sda = XS1_PORT_1M;
in port inClk = XS1_PORT_1N;

//clock declarations
clock ppClk = XS1_CLKBLK_1;//pp clock
clock pwmClk = XS1_CLKBLK_2;//pwm clock


int main() {
    char yesNoMaybe = 0;
    ppStruct ppDatabase[TRANSDUCER_COUNT];
    pwmStruct pwmDatabase[TRANSDUCER_COUNT];
    i2c_master_if i2c[1];

    while(1)
    {
        yesNoMaybe = 0;

        while(yesNoMaybe != 'y')
        {
            goLine <: 0;
            restartLine <: 0;
            quitLine <: 0;

            //all sorts of crazy
            dataProcessor(ppDatabase, pwmDatabase);

            par
            {
                i2c_master(i2c, 1, p_scl, p_sda, 400);
                adaSet(i2c[0], ppDatabase[0]);
            }
            clkSet();

            //asking if ready to go
            printstr("Data recieved and processed! 'y' to commence "
                    "testing, 'r' to restart or 'q' to quit: ");
            yesNoMaybe = getchar();
            fflush(stdin);
            switch(yesNoMaybe)
            {
            case 'y':
                goLine <: 1; //tell slave microcontrollers to start outputs
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

        start_clock(ppClk);
        start_clock(pwmClk);

        /*STUFF HAPPENS NOW*/
        par
        {
            //2 pwm outputs per core - 4 cores
            par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                pwmDrive(pwmDatabase[2*i], pwmDatabase[(2*i) + 1], pwm[2*i], pwm[(2*i) + 1], synchPulse[i]);
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
    }

    //introduce PP_DELAY to every pp
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        ppD[i].phase = ppD[i].phase + PP_DELAY;
        ppD[i].burstWait = (REF_RATE/ppD[i].brf) -
                (REF_RATE*ppD[i].burstLength/ppD[i].prf);//-2
        ppD[i].pulseWait = (REF_RATE/ppD[i].prf) -
                (REF_RATE*ppD[i].pulseLength/ppD[i].frequency);//-2
    }
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        pwmD[2*i].magPhase = 0;
        pwmD[(2*i) + 1].magPhase = 0;
        pwmD[(2*i) + 1].magPhase = pwmPhaser(pwmD[2*i], pwmD[(2*i) + 1]);
    }
}


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

    //convert text between '.' (parameters) from char to int
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
        //printf("%d\n",data[i]); //debugging
    }

    if (_close(fd) != 0)
    {
        printstrln("Error: _close failed. Exiting.");
        exit(1);
    }
}


//introduces phase shifts in pwm for optimising purposes
short pwmPhaser(pwmStruct pwmD1, pwmStruct pwmD2)
{
    int roundTo5MagRatio = 0;
    roundTo5MagRatio = 5*(int)round(pwmD1.magRatio / 5);

    if(roundTo5MagRatio + pwmD2.magRatio + 5 != 50)
    {
        if(roundTo5MagRatio + pwmD2.magRatio + 5 - 50 == pwmD1.magRatio)
        {
            pwmD2.magPhase == roundTo5MagRatio + 10;//arbitrary phase addition
        }
        else
        {
            pwmD2.magPhase == roundTo5MagRatio + 5;
        }
    }
    else
    {
        if(roundTo5MagRatio + pwmD2.magRatio + 10 - 50 == pwmD1.magRatio)
        {
            pwmD2.magPhase == roundTo5MagRatio + 15;//arbitrary phase addition
        }
        else
        {
            pwmD2.magPhase == roundTo5MagRatio + 10;
        }
    }
    if(pwmD2.magPhase > 50)
    {
        pwmD2.magPhase -= 50;
    }
    return pwmD2.magPhase;

}


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

    if(ppD.multisynthNum == 0)
    {
        setupMultisynthInt(i2c, ada, 0, SI5351_PLL_A, ppD.multisynthDiv);
    }
    else
    {
        setupMultisynth(i2c, ada, 0, SI5351_PLL_A, ppD.multisynthDiv, ppD.multisynthNum, ppD.multisynthDenom);
    }

    enableOutputs(i2c, ada, true);
}


//clocks things over the head
void clkSet()
{
    configure_clock_src(ppClk, inClk);
    configure_clock_ref(pwmClk, 0);//2MHz at 50 tick waveperiod

    //link 4 bit ports to ppClk. Initial out = 0
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        configure_out_port(pp[i], ppClk, 0);
    }
    //link 1 bit ports to pwmClk. Initial out = 0
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        configure_out_port(pwm[i], pwmClk, 0);
    }
}


//drives pwm outputs
void pwmDrive(pwmStruct pwmD1, pwmStruct pwmD2,
        out buffered port:1 p1, out buffered port:1 p2, streaming chanend synchPulse)
{
    int synch = 0;
    //current output values
    int currentDrive[4] = {1,1,0,0};
    //t1 controls first transducer, t2 controls second transducer
    unsigned int t1 = 20;//20 is arbitrarily added to minimise timing error
    unsigned int t2 = 20 + pwmD2.magPhase;//test this

    //saturated pwm detection
    if(pwmD1.magRatio == 50)
    {
        currentDrive[0] = 1;
        currentDrive[2] = 1;
        pwmD1.magRatio = 25;
    }
    else if(pwmD1.magRatio == 0)
    {
        currentDrive[0] = 0;
        currentDrive[2] = 0;
        pwmD1.magRatio = 25;
    }

    if(pwmD2.magRatio == 50)
    {
        currentDrive[1] = 1;
        currentDrive[3] = 1;
        pwmD2.magRatio = 25;
    }
    else if(pwmD2.magRatio == 0)
    {
        currentDrive[1] = 0;
        currentDrive[3] = 0;
        pwmD2.magRatio = 25;
    }
    unsigned int magRatioInverse1 = 50 - pwmD1.magRatio;
    unsigned int magRatioInverse2 = 50 - pwmD2.magRatio;

    while(1)
    {
        select
        {
        case synchPulse :> synch://returns if test has ended
            if(synch == 1)
            {
                return;
            }
            break;
        default://main drive loop
            p1 @ t1 <: currentDrive[0];
            p2 @ t2 <: currentDrive[1];
            t1 += pwmD1.magRatio;
            t2 += pwmD2.magRatio;
            p1 @ t1 <: currentDrive[2];
            p2 @ t2 <: currentDrive[3];
            t1 += magRatioInverse1;
            t2 += magRatioInverse2;
            break;
        }
    }
}


//drives pp outputs
void freqDrive(ppStruct ppD1, ppStruct ppD2, out buffered port:4 p, streaming chanend synchPulse)
{
    unsigned int t1 = ppD1.phase;
    unsigned int t2 = ppD2.phase;
    //t1 controls the 2 LSB (first transducer) and t2 controls the 2 MSB (last transducer)
    signed int phaseDifference = t1 - t2;
    unsigned int currentDrive = 5;//01|01 in binary
    p <: currentDrive;
    synchPulse <: 0;

    //main drive loop
    while(1) //for(size_t i=0; i < testLength; ++i)
    {
        while(1) //for(size_t i = 0; i < burstLength; ++i)
        {
            if(phaseDifference == 0)//if both transducers are of the same phase
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 10; t1 += HALF_WIDTH;//10|10
                    p @ t1 <: currentDrive = 5; t1 += HALF_WIDTH;//01|01
                }
            }
            else if(phaseDifference == HALF_WIDTH)//if first transducer is 180 phase behind
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t2 <: currentDrive = 9; t2 += HALF_WIDTH;//10|01
                    p @ t2 <: currentDrive = 6; t2 += HALF_WIDTH;//01|10
                }
            }
            else if(phaseDifference == -HALF_WIDTH)//if second transducer is 180 phase behind
            {
                for(size_t i = 0; i < ppD1.pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 6; t1 += HALF_WIDTH;//01|10
                    p @ t1 <: currentDrive = 9; t1 += HALF_WIDTH;//10|01
                }
            }
            else if(abs(phaseDifference) > HALF_WIDTH)
            {
                if(t1 < t2)
                {
                    p @ t1 <: currentDrive = 6;//01|10
                    t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 5;//01|01
                    t1 += HALF_WIDTH;
                    for(size_t i = 0; i < ppD1.pulseLength - 1; ++i)
                    {
                        p @ t2 <: currentDrive = 9;//10|01
                        p @ t1 <: currentDrive = 10;//10|10
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t2 <: currentDrive = 6;//01|10
                        p @ t1 <: currentDrive = 5;//01|01
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                    p @ t2 <: currentDrive = 9;//10|01
                    t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 5;//01|01
                    t2 += HALF_WIDTH;
                }
                else
                {
                    p @ t2 <: currentDrive = 9;//10|01
                    t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 5;//01|01
                    t2 += HALF_WIDTH;
                    for(size_t i = 0; i < ppD1.pulseLength - 1; ++i)
                    {
                        p @ t1 <: currentDrive = 6;//01|10
                        p @ t2 <: currentDrive = 10;//10|10
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t1 <: currentDrive = 9;//10|01
                        p @ t2 <: currentDrive = 5;//01|01
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                    p @ t1 <: currentDrive = 6;//01|10
                    t1 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 5;//01|01
                    t1 += HALF_WIDTH;
                }
            }
            else
            {
                if(t1 < t2)
                {
                    for(size_t i = 0; i < ppD1.pulseLength; ++i)
                    {
                        p @ t1 <: currentDrive = 6;//01|10
                        p @ t2 <: currentDrive = 10;//10|10
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t1 <: currentDrive = 9;//10|01
                        p @ t2 <: currentDrive = 5;//01|01
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
                }
                else
                {
                    for(size_t i = 0; i < ppD1.pulseLength; ++i)
                    {
                        p @ t2 <: currentDrive = 9;//10|01
                        p @ t1 <: currentDrive = 10;//10|10
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                        p @ t2 <: currentDrive = 6;//01|10
                        p @ t1 <: currentDrive = 5;//01|01
                        t1 += HALF_WIDTH;
                        t2 += HALF_WIDTH;
                    }
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
    synchPulse <: 1;//tell pwm to finish and return
    return;
}
