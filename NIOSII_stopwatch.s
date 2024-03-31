#Project 2 Part B
#use button 0 to pause and button 1 to restart count
.global _start
.equ O_7SEG_LO,     0x20
.equ O_7SEG_HI,     0x30
.equ O_UART,        0x1000
.equ O_BUTTONS,     0x50
.equ MMIO_BASE,     0xff200000
.equ PPI_INT_MASK,  0x58
.equ IRQ_SILENCE,   0x2000
.equ EDGE_CAP,      0x5c
.equ LO_TIMER,      0x2008
.equ HI_TIMER,      0x200C
.section .reset,    "ax"
_start:
	movia	sp, 0x100000
	movia	gp, MMIO_BASE
	br main

#################################ISR###########################
	.section .exceptions, "ax"
	rdctl	et, ipending
	bne	    et, r0, HardwareInterrupt
	eret
HardwareInterrupt:
	subi	ea, ea, 4		#back to code before interrupt
	subi	sp, sp, 36
	stw		r2, 0(sp)
	stw		r9, 4(sp)
	stw		r7, 8(sp)
	stw		r5, 12(sp)
	stw		r6, 16(sp)
	stw		r7, 20(sp)
	stw		r8, 24(sp)
	stw		r17, 28(sp)
	stw		ra, 32(sp)

#int flag irq1
	andi	r2, et, 0x2
	beq		r2, r0, notIRQ1
#irq mapped to button 1
	ldwio	r2, EDGE_CAP(gp)	
	stwio	r2, EDGE_CAP(gp)	

notIRQ1:
    andi	r2, et, 0x1
	beq		r2, r0, notIRQ0

#timer interrupt
	stwio	r0, IRQ_SILENCE(gp)	 #silence irq0
	
	movi r2, 1
	stw     r2, int_flag(r0)
	
	# Example:
	ldw		r7, Count(r0)
	addi	r7, r7, 1
	stw		r7, Count(r0)
	
	call	convertNum

notIRQ0:

ISR_END:
	ldw		r2, 0(sp)
	ldw		r9, 4(sp)
	ldw		r7, 8(sp)
	ldw		r5, 12(sp)
	ldw		r6, 16(sp)
	ldw		r7, 20(sp)
	ldw		r8, 24(sp)
	ldw		r17, 28(sp)
	ldw		ra, 32(sp)
	addi	sp, sp, 36
	eret	
.text

main:
	#irq0 Timer 1 setup
	movia	r2, 1000000
	stwio	r2, LO_TIMER(gp)	# Lo 16 bits to Timer Start Value
	srli	r2, r2, 16
	stwio	r2, HI_TIMER(gp)	# Hi 16 bits to Timer Start Value
	movi	r2, 0x7		
	stwio	r2, 0x2004(gp)

    #ienable bits setup
	movi 	r2, 3			#irq0, irq1 enable
	wrctl	ienable, r2 	
	
	movi 	r2, 1
	wrctl	status, r2       #pie bit on
    stwio   r2, 0x20(gp)		# load in seven seg display address
	stwio   r2, 0x30(gp)		# load in
	
    call    start_count

#######################delay function################################
# delays n miliseconds with delay loop, n stored in r7
delay:
	movi   	r7, 10				# multiply by n
	movui  	r2, 6000           # calculated number to delay by 10 ms
	mul		r2, r2, r7		# multiply int N by 10ms number to get 10*N ms delay loop

delay_loop:
	ldw     r2, int_flag(r0)
	beq     r2, r0, delay
	stw     r0, int_flag(r0)
	subi    r2, r2, 1              #1st clock
	bne     r2, r0, delay_loop     #2nd clock
	ret
	
delay_for_flag:
	ldw     r2, int_flag(r0)
	beq     r2, r0, delay_for_flag
	stw     r0, int_flag(r0)
	ret

#####################output_LED function################################
# LED counter
output_LEDS:
	ldwio   r9, (gp)			# led value into r9
	addi    r9, r9, 1			# add 1 to r9
	stwio   r9, (gp)			# output to LEDS
	movi    r7, 10			# move 10 to r7
	
    call delay			    # delay n milliseconds count with leds

#######################putchar function##############################
putchar:
	movi    r9, 4(sp)
	ldwio   r2, O_UART(r11) 						
	stwio   r9, O_UART(r11)
	ret

#################convertNum recursive function####################
convertNum_recursive:
	subi    sp, sp, 8
	stw     ra, 4(sp)
	movi    r8, 10                 #move 10 to r8 do divide
	
    #get remainders
	div     r5, r7, r8
	mul     r6, r5, r8
	sub     r6, r7, r6
	stw     r6, 0(sp)       #store remainder

    # recursively call function for next remainder if n >= 10
    blt     r7, r8, adder 
	mov     r7, r5
	
    call convertNum_recursive

adder:
    ldw     r6, 0(sp)           # load remainder
	addi    r7, r6, '0'         # add using ascii '0'
	call    putchar
	
	ldw     ra, 4(sp)
	addi    sp, sp, 8
	ret

####################convertNum non-recursive##########################
convertNum:
	subi    sp, sp, 12		
	stw     ra, 4(sp)
	movi    r8, 10 
	
    #get remainders
	div     r5, r7, r8
	mul     r6, r5, r8
	sub     r6, r7, r6
	stw     r6, 0(sp)
	mov     r2, r0
	blt     r7, r8, base 
	mov     r7, r5		
	
    call convertNum	

######################base case for convertNum####################
# called if r7<=r8  r8=10
base:					
	ldw     r6, 0(sp)
	slli    r2, r2, 8
	ldb     r9, Bits7Seg(r6)		
	or      r2, r2, r9
	ldw     ra, 4(sp)     
	addi    sp, sp, 12	
	ret

######################push button state machine######################	
start_count:
	movi    r20, 0 # Set all seven seg registers to 0
	movi    r23, 0
	movi    r25, 0 #hundreths
	movi    r22, 0 #minutes
	
reset_display:
	movia   r16, 0x3f3f3f3f #initialize each display to 0
	stwio   r16, 0x20(gp)
	stwio   r16, 0x30(gp)
	
    br check_incriment_move

sm_loop:
	ldwio   r2, O_BUTTONS(gp)
	andi    r12, r2, 1      #button 0 value
	andi    r14, r2, 2      #button 1 value
	beq     r13, r0, state_keep
	bne     r12, r0, state_keep
    xori    r20, r20, 1 # can only be true if only one is true
	movi    r23, 0 # frozen = false. sets frozen to 0
	
##########################state keep function#########################
#helper function for state_keeper
state_keep:
    beq     r15, r0, state_keeper
	bne     r14, r0, state_keeper
	beq     r20, r0, reset_registers
	xori    r23, r23, 1 #inverts frozen bit
	
	br state_keeper

#reset registers for counting		
reset_registers:
	movi    r25, 0
	movi    r22, 0
	movia   r16, 0x3f3f3f3f #reset all displays to 0
	stwio   r16, O_7SEG_LO(gp)
	stwio   r16, O_7SEG_HI(gp)

state_keeper:

	#move current into old states
	mov     r13, r12
	mov     r15, r14
	bne     r23, r0, check_incriment_move
	mov     r7, r25			
	
	call convertNum
	
	mov     r17, r2 
    mov     r7, r22  
	
	call convertNum
	
	mov     r18, r2
	movi    r24, 0x7e
	add     r19, r18, r17
	beq     r19, r24, reset_display
    stwio   r17, 0x20(gp)  # write to the seven seg display
	stwio   r18, 0x30(gp)

check_incriment_move:
	beq     r20, r0, sm_loop # check if equal to zero
	
    call    delay_for_flag
	
    addi    r25, r25, 1		
	movi    r2, 6000
	blt     r25, r2, sm_loop 
	addi    r22, r22, 1    
	movi    r25, 0			
	
    br check_incriment_move

.data
int_flag:	.word 0
Count:	    .word 0
Bits7Seg:
#      0	 1		2	  3		4	  5		6	  7 	8	 9
.byte 0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f