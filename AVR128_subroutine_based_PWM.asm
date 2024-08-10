; PWM_100_levels_intr
; subroutine_isr_based_display.asm
;
; Created: 11/29/2023 4:41:00 PM
; Author : Michael Bove
;

;
; PWM_100_levels.asm
;
; Created: 11/10/2023 3:46:22 PM
; Author : Michael
;

     .CSEG

     ; interrupt vector table, with several 'safety' stubs
 SETUP:
	jmp RESET
	
	 

.org PORTE_PORT_vect
	jmp porte_isr

	reti            ;External Intr0 vector
     reti            ;External Intr1 vector


;**********************************************************************
;************* M A I N   A P P L I C A T I O N   C O D E  *************
;**********************************************************************

RESET:
   sbi VPORTA_DIR, 7		; set PA7 = output.                   
   sbi VPORTA_OUT, 7		; set /SS of DOG LCD = 1 (Deselected)
   rcall init_lcd_dog    ; init display, using SPI serial interface
   rcall clr_dsp_buffs   ; clear all three SRAM memory buffer lines
   rcall update_lcd_dog		;display data in memory buffer on LCD
   ;load_line_1 into dbuff1:
   ldi  XH, high(dsp_buff_1)  ; pointer to line 1 memory buffer
   ldi  XL, low(dsp_buff_1)   ;
   rcall setting_message
   rcall update_lcd_dog		;breakpoint here to see blanked LCD
   
start:
	ldi r17, 0x00	;load 0s into r17
    out VPORTC_DIR, r17 ;initializes VPORTC to all inputs
	ldi r17, 0xFF	;load 1s into r17
	out VPORTD_DIR, r17 ;initializes VPORTC to be all outputs

	//setup interrupts
	push r16 //push current value if r16
	lds r16, PORTE_PIN0CTRL ;set ISC for PE0 to pos. edge
	ori r16, 0x02
	sts PORTE_PIN0CTRL, r16
	pop r16 //pop r16 original data back

pointer_setup:
	ldi r17, 0xFF
	out VPORTD_OUT, r17 ;initializes all LEDs to be turned off
	ldi XH, HIGH(dsp_buff_2+7) ;setup X pointer register to first number
	ldi XL, LOW(dsp_buff_2+7)
	ldi YH, HIGH(dsp_buff_2+8) //setup Y pointer register to right of first number
	ldi YL,LOW(dsp_buff_2+8)
	ldi r24, 0 //keep track of how many numbers were entered--initialized to 1 
	push r16 //save r16 status
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	ldi r20, 0x00 //used to reset LCD
	ldi r19, 0x00
	sei //set global interrupt

//main program
loop:
	sbrc r20, 0 //check clear flag
	jmp pointer_setup //if clear flag set, reset program (enable in memory flag during interrupt)
	sbrc r19, 0 //check if enter flag set, reset program (enable in memory flag during interrupt)
	jmp update_led //update PWM
	cpi r17, 0 //compares iteration count to 0
	brne check_ic_dc  //jump to compare_values if r17 doesn't equal 0
	
compare_values:
	cpi r17, 0 //checks iteration count
	brne check_ic_dc //if iteration count isn't 0, just branch to check if IC = DC
	cpi r23, 0
	breq check_ic_dc //if duty cycle is 0, jump to check_ic_dc
	
start_pulse:
	sbi VPORTD_OUT, 0 //set PD0 to 1 for start of pulse

check_ic_dc:
	cpi r17, 255 //check if duty cycle = 255
	breq increment //if duty cycle equals 255, branch to increment
	cp r23, r17 //check if duty cycle = iteration count
	brne increment //if increment count doesn't equal duty cycle, increment register

end_pulse:
	cbi VPORTD_OUT, 0 //turn PD0 to 0 for end of pulse

increment:
	inc r17 //increment iteration count
	rjmp loop //jump back to main_loop

update_led:
	ldi r19, 0x00
	rcall bcd_conversion //convert to decimal 0 - 100
	ldi r17, 0 //start iteration count at 0
	rcall pulse_width //map value from 0 - 255
	push r16
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16
	sei //re-enable global interrupt
	jmp loop //continually loop for PWM

porte_isr:
key_press:
	cli
	push r16 //save r16 status
	in r16, CPU_SREG //save status register status
	push r16
store_value:
	in r18, VPORTC_IN ;stores value for key press in register r18
map_value:
	lsr r18 ;right shift r18 4 times
	lsr r18	;get 4 MSBs to rightmost position
	lsr r18
	lsr r18
	rcall lookup

check_input:
	clear_key:
	cpi r18, $41 //compares with clear key
	brne enter_key
	ldi r20, 0x01 //set flag to indicate to clear LCD
	reti
	enter_key: //if enter key, update the LED to that percentage on
	cpi r18, $43
	brne display_value //if it's not enter key, just display value
	//otherwise, if enter key
	ldi r19, 0x01 //set r19 flag to indicate the enter key was pressed
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	out CPU_SREG, r16
	pop r16
	sei //re-enable global interrupt
	reti 

display_value:
case0:
	cpi r24, 0
	brne case1
	st X, r18  //decrement X, store it in r18
	inc r24 ;update number of characters entered
	rcall update_lcd_dog
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	out CPU_SREG, r16 //return status register status
	pop r16
	sei //re-enable global interrupt
	reti
	case1:
	cpi r24, 1
	brne case2
	rcall shift_memory_1
	rcall update_lcd_dog
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	out CPU_SREG, r16 //return status register status
	pop r16
	sei //re-enable global interrupt
	reti
	case2:
	cpi r24, 2
	brne case3
	rcall bcd_conversion
	cpi r23, 10 //check if r23's mapped value is 10
	brne key_press //if it's not, jump back to keypress (can't enter anymore values)
	cpi r18, 0x30 //compare key pressed to a 0 (if the mapped value is a 10)
	brne key_press //if it's not, jump back to wait for key press
	rcall shift_memory_2 //shift memory if it's a 0 (to get a 100)
	rcall update_lcd_dog
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	out CPU_SREG, r16 //return status register status
	pop r16
	sei
	reti
	case3:
	ldi r16, PORT_INT0_bm	
	sts PORTE_INTFLAGS, r16 ;clear IRQ flag for PE0
	pop r16 //return r16 original status
	out CPU_SREG, r16 //return status register status
	pop r16 //return r16 to r16
	sei
	reti



;---------------------------- SUBROUTINES ----------------------------


;====================================
.include "lcd_dog_asm_driver_avr128.inc"  ; LCD DOG init/update procedures.
;====================================


;************************
;NAME:      clr_dsp_buffs
;FUNCTION:  Initializes dsp_buffers 1, 2, and 3 with blanks (0x20)
;ASSUMES:   Three CONTIGUOUS 16-byte dram based buffers named
;           dsp_buff_1, dsp_buff_2, dsp_buff_3.
;RETURNS:   nothing.
;MODIFIES:  r25,r26, Z-ptr
;CALLS:     none
;CALLED BY: main application and diagnostics
;********************************************************************
clr_dsp_buffs:
     ldi R25, 48               ; load total length of both buffer.
     ldi R26, ' '              ; load blank/space into R26.
     ldi ZH, high (dsp_buff_1) ; Load ZH and ZL as a pointer to 1st
     ldi ZL, low (dsp_buff_1)  ; byte of buffer for line 1.
   
    ;set DDRAM address to 1st position of first line.
store_bytes:
     st  Z+, R26       ; store ' ' into 1st/next buffer byte and
                       ; auto inc ptr to next location.
     dec  R25          ; 
     brne store_bytes  ; cont until r25=0, all bytes written.
     ret

;*******************
;NAME:      load_msg
;FUNCTION:  Loads a predefined string msg into a specified diplay
;           buffer.
;ASSUMES:   Z = offset of message to be loaded. Msg format is 
;           defined below.
;RETURNS:   nothing.
;MODIFIES:  r16, Y, Z
;CALLS:     nothing
;CALLED BY:  
;********************************************************************
; Message structure:
;   label:  .db <buff num>, <text string/message>, <end of string>
;
; Message examples (also see Messages at the end of this file/module):
;   msg_1: .db 1,"First Message ", 0   ; loads msg into buff 1, eom=0
;   msg_2: .db 1,"Another message ", 0 ; loads msg into buff 1, eom=0
;
; Notes: 
;   a) The 1st number indicates which buffer to load (either 1, 2, or 3).
;   b) The last number (zero) is an 'end of string' indicator.
;   c) Y = ptr to disp_buffer
;      Z = ptr to message (passed to subroutine)
;********************************************************************
load_msg:
     ldi YH, high (dsp_buff_1) ; Load YH and YL as a pointer to 1st
     ldi YL, low (dsp_buff_1)  ; byte of dsp_buff_1 (Note - assuming 
                               ; (dsp_buff_1 for now).
     lpm R16, Z+               ; get dsply buff number (1st byte of msg).
     cpi r16, 1                ; if equal to '1', ptr already setup.
     breq get_msg_byte         ; jump and start message load.
     adiw YH:YL, 16            ; else set ptr to dsp buff 2.
     cpi r16, 2                ; if equal to '2', ptr now setup.
     breq get_msg_byte         ; jump and start message load.
     adiw YH:YL, 16            ; else set ptr to dsp buff 2.
        
get_msg_byte:
     lpm R16, Z+               ; get next byte of msg and see if '0'.        
     cpi R16, 0                ; if equal to '0', end of message reached.
     breq msg_loaded           ; jump and stop message loading operation.
     st Y+, R16                ; else, store next byte of msg in buffer.
     rjmp get_msg_byte         ; jump back and continue...
msg_loaded:
     ret
	
setting_message:
	ldi r24, 0 //set count to 0
	ldi  XH, high(dsp_buff_1)  ; pointer to line 1 memory buffer
    ldi  XL, low(dsp_buff_1)   
	ldi r22, 'D'
	st X+, r22
	ldi r22, 'u'
	st X+, r22
	ldi r22, 't'
	st X+, r22
	ldi r22, 'y'
	st X+, r22
	ldi r22, ' '
	st X+, r22
	ldi r22, 'C'
	st X+, r22
	ldi r22, 'y'
	st X+, r22
	ldi r22, 'c'
	st X+, r22
	ldi r22, 'l'
	st X+, r22
	ldi r22, 'e'
	st X+, r22
	ldi r22, ' '
	st X+, r22
	ldi r22, 'S'
	st X+, r22
	ldi r22, 'e'
	st X+, r22
	ldi r22, 't'
	st X+, r22
	ldi r22, 't'
	st X+, r22
	ldi r22, 'i'
	st X+, r22
	ldi r22, 'n'
	st X+, r22
	ldi r22, 'g'
	st X+, r22
	ldi r22, ' '
	st X+, r22
	ldi r22, '='
	st X+, r22
	ldi r22, ' '
	st X+, r22
	ldi r22, '0'
	st X+, r22
	ldi r22, '0'
	st X+, r22
	ldi r22, '0'
	st X+, r22
	ldi r22, '%'
	st X, r22
	ldi XH, HIGH(dsp_buff_2+7) ;setup X pointer register to first number
	ldi XL, LOW(dsp_buff_2+7)
	ldi YH, HIGH(dsp_buff_2+8) //setup Y pointer register to right of first number
	ldi YL,LOW(dsp_buff_2+8)
	ret

shift_memory_1:
	//stores what's at last index and stores in r17
	ld r17, X
	st -X, r17 //stores what's in r18 at index to left
	st -Y, r18
	inc r24
	rcall update_lcd_dog
	ret

shift_memory_2:
	ldi YH, HIGH(dsp_buff_2+8)
	ldi YL,LOW(dsp_buff_2+8)
	ld r17, X
	st -X, r17 //stores what's in r18 at index to left
	adiw XH:XL, 2
	ld r17, X
	st -X, r17
	st -Y, r18
	inc r24
	rcall update_lcd_dog
	ret

lookup:
	ldi ZH, high (segtable * 2) ;set Z to point to start of table
	ldi ZL, low (segtable * 2)
	ldi r17, $00 ;add offset to Z pointer
	add ZL, r18
	adc ZH, r17
	lpm r18, Z ;load byte from table pointed to by Z
	sec ;set carry to indicate valid result
	ret
	
;Table of segment values to display digits 0-9, 1 => ON
;map each key to corresponding hexadecimal value
segtable: .db $31, $32, $33, $30, $34, $35, $36, $30, $37, $38, $39, $30, $41, $30, $30, $43

bcd_conversion: //map a 3 digit BCD number to decimal
	ldi ZH, HIGH(dsp_buff_2+5) //get leading digit in  
	ldi ZL, LOW(dsp_buff_2+5)
	ld r22, Z //r12 stores leading digit
	andi r22, 0x0F //mask out leading hexa
	mov r23, r22 //copy r12 into r13
	lsl r22 //shift r12 to left by one (multiply by 2)
	lsl r23 //shift copy to left by 3 (multiply by 8)
	lsl r23
	lsl r23
	add r23, r22 //r13 = r12 + r13 (for DS2--get DS2 * 10)
	ldi ZH, HIGH(dsp_buff_2+6) //get second digit
	ldi ZL, LOW(dsp_buff_2+6)
	ld r22, Z //load second digit
	andi r22, 0x0F //mask out leading hexa
	add r23, r22 //r13 = DS2 + DS1
	mov r25, r23 //copy r13 and store it in r14
	lsl r23 //shift left by one (multiply by 2)
	lsl r25
	lsl r25
	lsl r25 //shift left by 3 (multiply by 8)
	add r23, r25 //add two shifted registers to get format DS2 * 100 + DS1 * 10
	ldi ZH, HIGH(dsp_buff_2+7) //get last digit
	ldi ZL, LOW(dsp_buff_2+7)
	ld r22, Z
	andi r22, 0x0F //mask out leading hexa
	add r23, r22 //get final format r23 = (10(10DS2 + DS1)) + DS0 
	ret			//r23 stores decimal conversion
	

pulse_width: //generates respective duty cycle based on input from VPORTC_IN
	cpi r23, 0x65 //number from 0 to 100
	brlo lookup_duty_cycle //if true, branch to  lookup
	clc //otherwise, clear carry bit
	ldi r18, 0 //load r18 with zero to indicate invalid result
	ret 

lookup_duty_cycle:
	ldi ZH, high(duty_cycle_segtable * 2) //set Z pointer to beginning of table
	ldi ZL, low(duty_cycle_segtable * 2)
	ldi r18, 0 //initialize offset to be 0
	add ZL, r23
	adc ZH, r18 //add carry (if there is one) to Z pointer
	lpm r23, Z //load Z pointer into r23
	sec //set carry to indicate valid result
	ret

duty_cycle_segtable: .db 0, 2, 5, 7, 10, 12, 15, 17, 20, 23, 25, 28, 30, 33, 35, 38, 41, 43, 46, 48, 51, 53, 56, 59, 61, 64, 66, 69, 71, 74, 77, 79, 82, 84, 87, 89, 92, 95, 97, 100, 102, 105, 107, 110, 113, 115, 118, 120, 123, 125, 128, 131, 133, 136, 138, 141, 143, 146, 149, 151, 154, 156, 159, 161, 164, 167, 169, 172, 174, 177, 179, 182, 185, 187, 190, 192, 195, 197, 200, 203, 205, 208, 210, 213, 215, 218, 221, 223, 226, 228, 231, 233, 236, 239, 241, 244, 246, 249, 252, 255

;***** END OF FILE ******