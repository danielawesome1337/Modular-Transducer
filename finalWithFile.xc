/*
 * struct.xc
 *
 *  Created on: 29 May 2016
 *      Author: dsdan
 */


#include <stdio.h>
#include <stdlib.h>
#include <syscall.h>
#include <xs1.h>
#include <platform.h>
#include <timer.h>
#include <math.h>
#include <print.h>
#include <functionDecs.h>

//preprocessor
//TRANSDUCER_COUNT is number of transducers per microcontroller
//REF_RATE is the reference clock rate at 100MHz
//HALF_WIDTH is half length waveperiod of push/pull (pp) in ticks
//PP_DELAY is many ticks much pp is delayed by. To precharge capacitors
//DIVIDER is the number REF_RATE is divided by to set pp frequency
//BUFFER_SIZE is input data buffer from parameters text file
//DATA_LENGTH is the number of parameters
//SOURCE is path to parameters text file
#ifndef TRANSDUCER_COUNT
#define TRANSDUCER_COUNT 8
#endif
#define REF_RATE 100000000
#define HALF_WIDTH 25
#define PP_DELAY 100//600000000 for normal operation
#define DIVIDER 20000//20000 for 50 tick waveperiods upto 2MHz
#define BUFFER_SIZE 128
#ifndef DATA_LENGTH
#define DATA_LENGTH 22//8 each for phase and magRatio, 6 for rest
#endif
#define SOURCE "parameters.txt"

//port declarations
//3 1 bit ports used to communicate to slave microcontrollers
out port goLine = XS1_PORT_1I;
out port restartLine = XS1_PORT_1J;
out port quitLine = XS1_PORT_1K;

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

//clock declarations
clock ppClk = XS1_CLKBLK_1;//pp clock
clock pwmClk = XS1_CLKBLK_2;//pwm clock

int main() {
    char yesNoMaybe = 0;
    ppStruct ppDatabase[TRANSDUCER_COUNT];
    pwmStruct pwmDatabase[TRANSDUCER_COUNT];

    while(1)
    {
        yesNoMaybe = 0;
        goLine <: 0;
        restartLine <: 0;
        quitLine <: 0;
        while(yesNoMaybe != 'y')
        {
            //all sorts of crazy
            dataProcessor(ppDatabase,pwmDatabase);

            //asking if ready to go
            printstr("Data recieved and processed! 'y' to commence "
                    "testing, 'r' to restart or 'q' to quit:");
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
        ppD[i].topRatio = data[0];
        ppD[i].testLength = data[1];
        ppD[i].burstLength = data[2];
        ppD[i].brf = data[3];
        ppD[i].pulseLength = data[4];
        ppD[i].prf = data[5];
    }
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {

        ppD[i].phase = data[i + 6];
        pwmD[i].magRatio = data[i + 14];
    }

    //clockRate is the frequency at which ppClk will run at (REF_RATE*topRate/DIVIDER
    //rounded up to the closest REF_RATE/(2*n) where int n = 1 to 255)
    unsigned int clockRate = binaryChop(ppD[0].topRatio);

    //introduce PP_DELAY to every pp
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        ppD[i].phase = ppD[i].phase + PP_DELAY;
        ppD[i].burstWait = ((ppD[i].topRatio/ppD[i].brf) -
                (ppD[i].burstLength/ppD[i].prf))*clockRate;//-2
        ppD[i].pulseWait = ((ppD[i].topRatio/ppD[i].prf) -
                (ppD[i].pulseLength/ppD[i].topRatio))*clockRate;//-2
    }
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        pwmD[2*i].magPhase = 0;
        pwmD[(2*i) + 1].magPhase = pwmPhaser(pwmD[2*i], pwmD[(2*i) + 1]);
    }

    clockConfig(ppD[0].topRatio);
}


void dataCapture(unsigned int data[DATA_LENGTH])
{
    unsigned char readBuffer[BUFFER_SIZE];
    int fd;
    int flagCount = 0;
    unsigned int flags[BUFFER_SIZE];

    fd = _open(SOURCE, O_RDONLY, 0);
    if (fd == -1) {
        printstrln("Error: _open failed. Exiting.");
        exit(1);
    }
    _read(fd, readBuffer, BUFFER_SIZE);

    //flag every '.' in parameters text file
    for(size_t i = 0; i < BUFFER_SIZE; ++i)
    {
        if(readBuffer[i] == '.')
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


//find actual clockRate using binary chop algorithm
unsigned int binaryChop(unsigned int topRatio)
{
    int first = 0;
    int last = 255;
    int middle = round(first + last)/2;
    unsigned int clockRate = round((topRatio/DIVIDER)*1000000);

    unsigned int clockRateTable[256] = {REF_RATE};
    for(size_t i = 1; i < 256; ++i)
    {
        clockRateTable[i] = round(REF_RATE/(2*i));
    }

    while (first <= last)
    {
        if(clockRateTable[middle] == clockRate)
        {
            clockRate = clockRateTable[middle];
            return clockRate;
        }
        else if((clockRateTable[middle] < clockRate) && (clockRateTable[middle - 1] >= clockRate))
        {
            clockRate = clockRateTable[middle - 1];
            return clockRate;
        }
        else if(clockRateTable[middle] < clockRate)
        {
            last = middle - 1;
        }
        else
        {
            first = middle + 1;
        }
        middle = round(first + last)/2;
    }
    if (first > last)
    {
        printstr("clockRate could not be determined. Exiting.");
        exit(1);
    }
    return 0;
}


//clocks things over the head
void clockConfig(unsigned int topRatio)
{
    //second param/third param = ideal clock rate in MHz
    //this is rounded up to closest REF_RATE/(2*n) where int n = 1 to 255
    configure_clock_rate_at_least(ppClk, topRatio, DIVIDER);
    configure_clock_rate_at_least(pwmClk, 1000, 10);//2MHz at 50 tick waveperiod

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
            else if(t1 < t2)
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
            else//if t2 > t1
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
