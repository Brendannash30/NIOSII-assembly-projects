.global _start
.equ O_UART_DATA, 	0x1000
.equ O_UART_CTRL, 	0x1004
.equ O_7SEG_LO, 	0x20
.section .reset, "ax"
_start:
	movia	sp, 0x1000
	movia	gp, 0xff200000
	br main
##############################my code###################################################	
##########################ISR########################
	.section .exceptions, "ax"
	rdctl	et, ipending
	bne	et, r0, HardwareInterrupt
	eret
HardwareInterrupt:
	subi	ea, ea, 4		#rewind ea to restart aborted instruction
	subi	sp, sp, 36
	stw		r2, 0(sp)
	stw		r3, 4(sp)
	stw		r4, 8(sp)
	stw		r5, 12(sp)
	stw		r6, 16(sp)
	stw		r7, 20(sp)
	stw		r10, 24(sp)
	stw		r16, 28(sp)
	stw		ra, 32(sp)
#handle pushbutton IRQ#1
	ldwio	r2, 0x5c(gp)	# Buttons: EdgeCapture register
	stwio	r2, 0x5c(gp)	# Write a "1" to bits, to set to 0.

	ldw		r16, Count(r0)
	mov		r16, r0
	mov		r4, r16
	call	showNum
	stw		r16, Count(r0)
	
ISR_END:
	ldw		r2, 0(sp)
	ldw		r3, 4(sp)
	ldw		r4, 8(sp)
	ldw		r5, 12(sp)
	ldw		r6, 16(sp)
	ldw		r7, 20(sp)
	ldw		r10, 24(sp)
	ldw		r16, 28(sp)
	ldw		ra, 32(sp)
	addi	sp, sp, 36
	eret	
##########################################################	
.text 
main:

	movi	r2, 3			#Both button 0 and 1 generate IRQ1
	stwio	r2, 0x58(gp)	#pushbutton ppi interrupt mask
	
	movi 	r2, 2			#enable IRQ1
	wrctl	ienable, r2 	#enable <- 2
	
	movi 	r2, 1
	wrctl	status, r2

	
	######################################################
	mov		r16, r0
	mov		r4, r16
	call	showNum
		

loop_main:

	
	movia 	r4, Prompt
	call	puts
	
	movia	r4, Buffer
	call	gets
	
	movia	r4, Response
	call 	puts
	
	movia	r4, Buffer
	call	puts
	
	movia	r4, Buffer
	call	atoi
	
	mov		r15, r2
	
	ldw		r16, Count(r0)
	add		r16, r15, r16
	stw		r16, Count(r0)
	
	
	movi	r4, '\n'
	call 	putchar
	movia	r4, SumResponse
	call 	puts
	mov		r4, r16
	call	printNum
	
	
	mov	r4, r16
	call	showNum
	
stop: br loop_main


##############################Kooros code###########################
#####################################
# void showNum(int n) -- Convert n[0...9999] to 7-Seg bits
showNum:
	subi	sp, sp, 4
	stw		ra, (sp)
	
	call 	num2bits
	stwio	r2, O_7SEG_LO(gp)
	
	ldw		ra, (sp)
	addi	sp, sp, 4
	ret		
#####################################
# void num2bits(int n) -- Convert n[0...9999] to 7-Seg bits
num2bits:
	movi	r2, 0
	movi	r10, 10
	movi 	r7, 4
  n2b_loop:
	div		r3, r4, r10 				# r4 is quotient n/10
	mul		r5, r3, r10
	sub		r5, r4, r5					# r5 is remainder n%10
	ldbu	r6, Bits7seg(r5)			# Get 7seg bits for digit (n%10)
	or		r2, r2, r6
	roli	r2, r2, (32-8)				# rori r8, r8, 8
	mov		r4, r3
	subi	r7, r7, 1
	bgt		r7, r0, n2b_loop
	
	ret
	
# int printNum(int n) -- Print number to UART
# {
#	if(n  < 0){
#		putchar("-");
#		n = -n;
#	}
#	if (n < 10) {
#		putchar('0' + n);
#	}
#	else{
#		printNum(n / 10);
#		putchar('0' + (n % 10));
#	}
# }
printNum:
	subi	sp, sp, 8
	stw		ra, 4(sp)
	
	bge		r4, r0, not_neg
	sub		r4, r0, r4
	stw		r4, 0(sp)
	movi	r4, '-'
	call	putchar
	ldw 	r4, 0(sp)
  not_neg:

	movi	r10, 10					# if (n < 10)
	bge		r4, r10, not_base
	addi	r4, r4, '0'				#      putchar('0' + n);
	call	putchar
	br		printNum_done
	
  not_base:
	movi	r10, 10
	div		r3, r4, r10				# r3 = n /10
	mul		r5, r3, r10
	sub		r5, r4, r5				#r5 = n %10;
	stw		r5, 0(sp)
	mov		r4, r3
	call	printNum				# printNum(n / 10)
	ldw		r5, 0(sp)
	addi		r4, r5, '0'
	call	putchar					#putchar('0' + (n % 10));
	
  printNum_done:
	ldw		ra, 4(sp)
	addi	sp, sp, 8
	ret	
#####################################
# int atoi(char *str)-- Convert string to number using Horner's Algorithm
# {
# 	char c;
# 	int negate = 0;
# 	int sum = 0;
# 	if (*str == '-'){
#		negate = 1;
#   	str++;
# 	}
#	while ((c = *str++) >= 0 && c <='9'){
#		sum *= 10;
#		sum += c - '0';
#	}
#	return negate ? -sum : sum;
# }
atoi:
	movi	r2, 0				# sum = 0;
	movi 	r3, 0				#negate = 0;
	ldbu	r5, (r4)			# *str
	cmpeqi	r6, r5, '-'			#      == '-';
	beq		r6, r0, no_negate
	movi	r3, 1				# negate = 1;
  atoi_loop:	
	addi	r4, r4, 1			# str++;
	ldbu	r5, (r4)			# *str
  no_negate:
  	movi	r6, '0'
	blt		r5, r6, atoi_done
	movi 	r6, '9'
	bgt		r5, r6, atoi_done
	
	muli	r2, r2, 10			# sum *= 10;
	subi	r5, r5, '0'			# sum += c - '0';
	add		r2, r2, r5
	br		atoi_loop
  atoi_done:
  	beq		r3, r0, dont_negate
	sub		r2, r0, r2			# -sum
  dont_negate:
  	ret
#####################################
# void puts(char *str)
# char c:
# while ((c = *buf++)) != '\n') {
#	putchar(c);
# }
#}
puts:
	ldbu	r3, (r4)			# c = *buf
	addi	r4, r4, 1			# buf++
	beq		r3, r0, puts_done
	
	########## putchar() ############
	ldwio	r2, O_UART_CTRL(gp)
	srli	r2, r2, 16			#Validate WSPACE > 0
	beq		r2,	r0, putchar
	stwio	r3, O_UART_DATA(gp)
	########## putchar() ############
	br		puts
  puts_done:
	ret
#####################################
# void gets(char *buf) -- Read a line up to a '\n', return string
# char c:
# while ((c = getchar()) != '\n') {
#	*buf++ = c;
# }
# *buf = '\0'
#}
gets:
	########## getchar() ############
 	ldwio	r2, O_UART_DATA(gp)
	andi	r3, r2, 0x8000 
	beq		r3, r0, gets
	andi	r2, r2, 0xFF
	########## getchar() ############
	stwio	r2, O_UART_DATA(gp)
	movi	r3, '\n'
	beq		r2, r3, gets_done
	stb		r2, (r4)
	addi	r4, r4, 1
	br		gets
	
  gets_done:
  	stb		r0, (r4)	#*buf ='\0'
	ret

#####################################
# void putchar(char c)
putchar:
	ldwio	r2, O_UART_CTRL(gp)
	srli	r2, r2, 16
	beq		r2,	r0, putchar
	stwio	r4, O_UART_DATA(gp)
	ret
#####################################
# void getchar(char c)
getchar:
 	ldwio	r2, O_UART_DATA(gp)
	andi	r3, r2, 0x8000 
	beq		r3, r0, getchar
	andi	r2, r2, 0xFF
	ret

.data
Count:	.word 0

Buffer:
	.space 	100, 0
	
Prompt:
	.asciz	"\nEnter number: "
Response:
	.asciz	"You typed: "
SumResponse:
	.asciz	"Total = "
Bits7seg:
	#		 0    1    2    3    4    5    6    7    8    9
	.byte	0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x67
.end