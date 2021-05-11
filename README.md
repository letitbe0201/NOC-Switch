# NoC switch with permutation blocks

#### SUMMARY
This is a simple Network on Chip implementation of one switch transferring data to and from a testbench and four permutation blocks. The switch sends raw data to the perm blocks through an n2p_fifo, and later receives the encoded data from 4 perm blocks based on a priority round-robin manner. The perm blocks perform SHA-3 permutation algorithm [1], it has 64-bit in/out port and permutes data of 5x5x64. Project instructions, timing and area reports are placed in the directory doc/.


**Overview of the switch and FIFOs**
The noc_from_, and noc_to_ (green waveforms) ports are the switch pins connecting the testbench and 4 perm blocks. The n2o_fifo (red waveform) is the FIFO output to the perm blocks. The p2n_fifox_ (yellow waveforms) are the FIFO output to the NoC switch. As the figure shows, the switch sends the raw data to each of the perm block. Later, the perm blocks send the encoded data back after the data is permuted.

![Image of Boxes](https://raw.githubusercontent.com/letitbe0201/NOC-Switch/master/doc/fifos_acts.jpg)


***Referece:***
[1] Dworkin, M. (2015), SHA-3 Standard: Permutation-Based Hash and Extendable-Output Functions, Federal Inf. Process. Stds. (NIST FIPS), National Institute of Standards and Technology, Gaithersburg, MD, [online], https://doi.org/10.6028/NIST.FIPS.202 (Accessed Dec., 2020)