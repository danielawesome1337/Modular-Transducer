#include <xs1.h>

void test() {
	out port outClock = XS1_PORT_1A; %configure output port
	clock clk = XS1_CLKBLK_1; %configure clock block
	configure_clock_rate(clk, 100, 50); %2MHz clock rate for clock block
	configure_port_clock_output(outClock, clk); %output clock block through outClock
	start_clock(clk);
}

int main(void) {
	par{
		test(); %10 parallel outputs
		test();
		test();
		test();
		test();
		test();
		test();
		test();
		test();
		test();
	}
	return 0;
}