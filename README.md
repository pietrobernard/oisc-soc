# oisc-soc
## Introduction
This project is about a fully programmable System-on-Chip on Artyx FPGAs which consists in several modules attached to an internal 32-bit wide system bus. The core is a custom OISC processor, implementing the `SUBLEQ` paradigm. The SoC contains several modules:
- OISC CPU
- I2C transceiver
- Two UART transceivers
- SRAM controller (controls an external 128kb SRAM expansion module)
- VGA output at 240x160, 60Hz video signal
- Two 8-bit GPIO ports

<p align="center"><img src="https://digilent.com/reference/_media/reference/programmable-logic/arty/arty-2.png" width="300"></p>

These modules are connected to a shared internal 32-bit bus with arbitration that is organized in the following way:
```
bit index:  31                30 downto 8                 7 downto 0
meaning:    C                 AAAAAAAAAAAAAAAAAAAAAAA     DDDDDDDD
            Command (1 bit)   Address (23 bits)           Data (8 bits)
```
The core idea behind the SoC is that everything is memory mapped, so there are bot <b>physical</b> and <b>virtual</b> addresses.
- Each module attached to the bus has a specific address space.
- The address space of a given module is further partitioned between its internal sub-modules (if any).
- Specific functions of each device/sub-device can be attached to specific addresses.
- The address might correspond to:
  * Physical registers / SRAM memory locations
  * Logical registers (grouping of smaller physical ones)
  * Virtual registers (attached to specific device functions)

The CPU can then reach any device or sub-device in the SoC totally <b>transparently</b> by simple read/write operations, sometimes performing complex tasks with a single instruction.

## Internal Bus
Each SoC module is connected to the internal bus via a common interface. This handles the low level signalling that allows the data to be moved around the system.
- At any given time, the bus can be idle or there can be only one device that is mastering it.
- Once the bus is assigned by the arbiter to a master, all the other devices' bus interfaces enter in slave mode.
- When in slave mode, each interface listens for data directed/requested to/from them by comparing the transmitted address with their own address space.
- A transaction may consist in a single byte transfer or in multiple transfers, holding the bus busy.

If a device has internal sub-devices, these are attached to a device-wide secondary bus that shares the same logic and interface of the main bus. The connection between the two is done by means of a bridge.
<p align="center"><img src="./img/bus.png" width="600"></p>
This connection is completely transparent to the other devices, including the CU, that can then address the internal sub-devices as if they were connected to the main bus.

## CPU architecture - Internal Modules
The CPU contains two main modules: the core and the interrupt handler.
### Core
The core contains the fetch-execute cycle, the ALU, the internal registers and an additional sub-module that is used to do bit-manipulation. This is too memory mapped and so bit-manipulation is triggered by simply reading and writing to appropriate virtual registers. Here is a schema of the device's registers:
<p align="center"><img src="./img/regs.png"></p>


## OISC Core
### SUBLEQ instruction and Addressing Modes
The SoC core is an OISC processor that implements the `SUBLEQ` instruction which requires three operands A, B and C (more on addressing modes later)
```
  SUBLEQ  A  B  C
```
this instruction does the following:
```
  B = B - A
  IF (B <= 0) THEN jump to address C
  ELSE jump to next address
```
There are three addressing modes: immediate, direct and indirect.
- Immediate: the operand value is treated as data. This is specified with a "!" symbol right before the numerical value.
- Direct: the operand value is its memory address. No additional symbols are required to define this.
- Indirect: the operand value is an address that points to another address. This is specified by the "@" symbol right before the value.

In the following, some OISC assembly will be introduced. The comments are started with the ";" character, the labels instead are terminated with ":". Each line requires exactly three operands.
```
  ; initializing two memory locations labelled by T and V
  0:  T  T  +1  ; mem[T] = mem[T] - mem[T] = 0
  1:  V  V  +1  ; mem[V] = mem[V] - mem[V] = 0
  ; loading T with -2 and then moving it to V
  1: !2  T  +1  ; mem[T] = mem[T] - 2 = 0 - 2 = -2
  3:  T  V  +1  ; mem[V] = mem[V] - mem[T] = 0 - (-2) = +2
```
Another example with more complex indirect addressing with an array T with two elements (-2, -3):
```
; loading the address '1234' into memory location T
0:  T      T  +1      ; mem[T] = 0
1:  P      P  +1      ; mem[P] = 0
2:  !1234  P  +1      ; mem[P] = -1234
3:  P      T  +1      ; mem[T] = 1234
; clearing memory at address '1234'
4:  @T    @T  +1      ; mem[mem[T]] = 0
; placing value "-2" at base address 1234
5:  !2    @T  +1      ; mem[mem[T]] = -2
; incrementing the address by 1
6:  P      P  +1      ; mem[P] = 0     
7:  !1     P  +1      ; mem[P] = -1
8:  P      T  +1      ; mem[T] = 1234 - (-1) = 1235
; clearing memory at address '1235'
9:  @T    @T  +1      ; mem[mem[T]] = 0
; placing value "-3" at address 1235
10: !3    @T  +1      ; mem[mem[T]] = -3
```


## System design
The system is designed as a series of modules attached to the system bus via a common interface. The idea is that each module implements the same bus interface and signalling logic, so that creating a new module is straightforward since one does not need to care about re-creating the bus interfacing logic each time.

### Memory model
The initial driving phylosophy behind this project was to make it so each module, down to its registers, could be memory mapped.

### The system bus
The system bus is an internal 32-bit wide bus where bits `7:0` are reserved for the data byte, bits `30:8` are used for the address and the MSB `31` is the bus command bit. The bus also uses several control lines in order to properly orchestrate data transmission. These signals are automatically handled by the bus transceiver interface that each module implements.

#### Bus Arbitration and Mastering
The bus uses arbitration and at any given time only one module can be the master while all the other module transceivers are forced to stay either in standby or slave mode. A module may request to master the bus by rising an appropriate signal to the bus arbiter. An elementary logic prevents the same module from repeatedly owning the bus, effectively starving the other modules. Once a master has been granted the bus, it can initiate bus transactions with other modules. Each module owns a specific set of memory addresses
