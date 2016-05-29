/*
 * clockTest.xc
 *
 *  Created on: 15 Jan 2016
 *      Author: Daniel
 */

#include <xs1.h>
#include <stdio.h>
#include <platform.h>
#include <timer.h>
[[combinable]]
void counter_task(char *taskId, int n) {
  int count = 0;
  timer tmr;
  unsigned time;
  tmr :> time;
  // This task perfoms a timed count a certain number of times, then exits
  while (1) {
    select {
    case tmr when timerafter(time) :> int now:
      printf("Counter tick at time %x on task %s\n", now, taskId);
      count++;
      if (count > n)
        return;
      time += 1000;
      break;
    }
  }
}
