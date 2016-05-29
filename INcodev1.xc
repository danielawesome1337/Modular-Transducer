/*
 * INcodev1.xc
 *
 *  Created on: 26 May 2016
 *      Author: dsdan
 */


#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stdio.h>
#include <stdlib.h>
#include <syscall.h>

#define BUFFER_SIZE 128
#define DATA_LENGTH 22
#define TRANSDUCER_COUNT 8
#define SOURCE "test.txt"

in port goLine = XS1_PORT_1I;
in port returnLine = XS1_PORT_1J;

int main() {
    unsigned char readBuffer[BUFFER_SIZE];
    int flagCount = 0;
    unsigned int data[DATA_LENGTH];
    unsigned int flags[BUFFER_SIZE];

    for(size_t i = 0; i < DATA_LENGTH; ++i)
    {
        data[i] = 0;
    }

    unsigned int topRatio;
    unsigned int testLength;
    unsigned int burstLength;
    unsigned int brf;
    unsigned int pulseLength;
    unsigned int prf;
    unsigned int magRatio[TRANSDUCER_COUNT];
    unsigned int phase[TRANSDUCER_COUNT];

    int fd = _open(SOURCE, O_RDONLY, 0);
    if (fd == -1) {
        printstrln("Error: _open failed");
        exit(1);
    }

    _read(fd, readBuffer, BUFFER_SIZE);

    for(size_t i = 0; i < BUFFER_SIZE; ++i)
    {
        if(readBuffer[i] == '.')
        {
            flags[flagCount] = i;
            flagCount++;
        }
    }

    for(size_t i = 0; i < DATA_LENGTH; ++i)
    {
        for(size_t j = flags[i]+1; j < flags[i+1]; ++j)
        {
            data[i] = data[i] * 10 + (readBuffer[j] - '0');
        }
        printf("%d\n",data[i]); //debugging
    }

    topRatio = data[0];
    testLength = data[1];
    burstLength = data[2];
    brf = data[3];
    pulseLength = data[4];
    prf = data[5];
    for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
    {
        magRatio[i] = data[i + 6];
        phase[i] = data[i + 14];
    }

    if (_close(fd) != 0)
    {
        printstrln("Error: _close failed.");
        exit(1);
    }


    printstr("Data recieved and processed!");
    select
    {
    case goLine when pinsneq(0) :> void:
        break;
    case returnLine when pinsneq(1) :> void:
        //return with dataIn
        break;
    }

    return 0;
}
