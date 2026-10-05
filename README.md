# Bare-Metal PIC16F877 Microcontroller Arithmetic Engine

A bare-metal embedded system written in PIC Assembly (MPASM) running on the **Microchip PIC16F877** microcontroller at **20MHz (HS Crystal)**. The firmware interfaces directly with physical hardware peripherals (16x2 character LCD, 4x4 matrix keypad, and discrete GPIOs) to execute a real-time, interactive mathematical quiz game without an underlying operating system

---

## Hardware Architecture & Peripheral Interfacing
```
                        +---------------------------+
                        |      PIC16F877 (20MHz)    |
                        +---------------------------+
                          |      |     |     |    |
   [Timer 0 Free-Run]-----+      |     |     |    +----[Timer 1 ISR (100ms)]
  (Entropy / Math RNG)           |     |     |                 |
                                 |     |     |                 +---> RC7 (5Hz Square Wave)
                                 |     |     |                       (Oscilloscope Monitored)
       +-------------------------+     |     +--------------------+
       |                               |                          |
 [PORTB 4x4 Keypad]             [PORTE Control: RE0=E, RE1=RS] [PORTA Pin 5]
 (Matrix Row/Col Scan)          [PORTD 8-bit Data Bus]         (Async Reset Button)
                                [16x2 Character LCD]
```

### Core Technical Highlights
* **Bare-Metal Low-Level Control:** Written completely in Assembly with direct register manipulation, bank switching macros (`BANK0`, `BANK1`), and memory-mapped I/O.
* **Precision Hardware Interrupts & Context Saving:**
  * Configured **Timer 1** with a 1:8 prescaler and preload value (`0x0BDC`) to trigger deterministic 100ms interrupts.
  * Preserved runtime execution context via swap operations into unbanked Common RAM (`0x70–0x7F`).
* **Real-Time Signal Toggling & Verification (RC7):**
  * Toggled `PORTC<7>` on every Timer 1 ISR tick (`xorwf PORTC,f`).
  * Produced a 5Hz continuous square wave monitored and verified in the lab using a digital storage oscilloscope.
* **Hardware-Based Entropy (Timer 0):**
  * Sampled free-running `TMR0` registers asynchronously upon user triggers.
  * Extracted 4-bit upper and lower nibbles with modulo-10 clamping to yield pseudo-random operands (0–9).
* **Direct Bus Peripheral Control:**
  * Implemented parallel 8-bit bus initialization and write cycles for the HD44780 LCD controller.
  * Managed 4x4 keypad matrix column-polling, row-driving, and software key-release debouncing on `PORTB`.
* **State Machine & Arithmetic Logic:**
  * Handles addition, subtraction (with negative result prevention via register swapping), multiplication, and integer division with divide-by-zero protection.

---

## Hardware Verification & Laboratory Results

### System in Operation
The system displays dynamically generated arithmetic expressions, runs a real-time countdown via ISR ticks, processes two-digit user keypad answers, updates scores, and handles timeouts.

  
https://github.com/user-attachments/assets/4f065bee-0b3a-47b8-a318-a38fca024fd2


### Real-Time Interrupt & Signal Analysis
To verify deterministic interrupt timing under execution load, `PORTC<7>` was measured using an **Agilent InfiniiVision DSO-X 3012A Digital Storage Oscilloscope**, confirming precise 100ms timing intervals without jitter.

 <img width="600" height="800" alt="IMG_9812" src="https://github.com/user-attachments/assets/c35ab41a-e476-4b50-9e50-1ab1c36e8247" />

---
### Keypad Operation & Function Mapping

| Key | Operation | Functionality |
|---|---|---|
| **A** | **Addition (+)** | Triggers addition of two pseudo-random digits |
| **B** | **Subtraction (-)** | Triggers subtraction with automatic operand swap to prevent negative results |
| **C** | **Multiplication (*)** | Triggers multiplication |
| **D** | **Division (/)** | Triggers integer division with divide-by-zero protection|
| **0–9** | **Digit Input** | Enters two-digit answer during the 5-second countdown |
| **PA5** | **Reset** | External push button to reset the accumulated score |

---

## Game State Machine & Scoring Logic

| Event | Score Adjustment | Behavior |
|---|---|---|
| **Correct Answer** | **+10** | Awarded on two-digit matching result |
| **Incorrect Answer** | **-5** | Clamped at minimum score |
| **Timeout (5 Seconds)** | **-3** | Triggered when 5s timer expires without answer |
| **Score Reset** | **Reset to 0** | Async active-low button press on `PA5`|

---

## Technical Specifications
* **Target Microcontroller:** Microchip PIC16F877 / PIC16F877A
* **Clock Frequency:** 20.0 MHz High-Speed (HS) Crystal (Instruction Cycle: 200ns)
* **Peripherals:** 16x2 Alphanumeric LCD (Parallel 8-bit mode), 4x4 Matrix Keypad, Push-Button Input
* **Toolchain:** Microchip MPLAB IDE / MPASM
* **Verification Instrument:** Agilent InfiniiVision DSO-X 3012A Digital Storage Oscilloscope

