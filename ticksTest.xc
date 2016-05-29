/*
 * ticksTest.xc
 *
 *  Created on: 27 May 2016
 *      Author: Daniel
 */

#include <stdio.h>
#include <stdlib.h>
#include <syscall.h>
#include <xs1.h>
#include <platform.h>
#include <timer.h>
#include <math.h>
#include <print.h>

int main()
{
    while(1)
    {
        delay_ticks(100000000);
        printintln(10);
    }
}
