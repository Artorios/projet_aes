;==============================================================================
; Essai d'implementation de la librairie à utiliser
; 
; Victor Perron 2009 - Projet AES
;==============================================================================


format ELF



; Include standard defs with proc, .if, etc
include 'inc/default.inc'


; Exporter les symboles necessaires
public  SetState
public  AesInit
public  AsmTest
public  DumpState
public  AddRoundKey
public	ShiftRows
public	ShiftRows_SSSE3
public	MixColumns
public	AesInitXmm

section '.text' executable
;==============================================================================
;      AesInit function : Si je retourne 1 tout va bien...
;==============================================================================
proc AesInit  

	; On veut la commande 1
	mov eax, 1
	cpuid 
	; On lit le resultat dans edx pour SSE et SSE2 (positions 25 & 26)
	shr edx, 25
	and edx, 03h

	; On lit le resultat pour les autres dans SSE3, etc.
	and ecx, 110000000001000000001b
	
	
	xor eax, eax
	; On place les bits SSE4
	rol ecx, 2
	mov ebx, ecx
	and ebx, 011b

	or  eax, ebx
	shl eax, 1
	 
	; On place les bits SSSE3
	rol ecx, 10
	mov ebx, ecx
	and ebx, 01b
	
	or  eax, ebx
	shl eax, 1

	; Puis SSE3
	rol ecx, 9
	mov ebx, ecx
	and ebx, 01b

	or  eax, ebx
	shl eax, 2

	; Enfin SSE2 et 1
	or eax, edx
		
	ret

endp


;==============================================================================
;      DStateMacro :	Used to dump the State of one XMM register into memory
;			Debug Purposes only
;==============================================================================
macro dstate xmmreg {
	movups	[edx], xmmreg   
}

;==============================================================================
;      Function : AddRoundKey : Load Memory-mapped RoundKey into XMM register
;				and performs XOR-BASE ciphering
;==============================================================================
proc AddRoundKey, v1
	mov	eax, [v1]

	;debug
	;mov	edx, [v2]

	; Load RoundKey into xmm1
	movups	xmm1, [eax]

	;debug
	;dstate	xmm1

	; Performs XOR-based encryption
	xorps	xmm0, xmm1

	ret
endp


;==============================================================================
;      Function : AesInit
;		Loads some matrixes from memory into xmm registers in order
;		to optimize speed

;==============================================================================

proc AesInitXmm
	lea	eax, [mixtable1]
	lea	ebx, [mixtable2]

	movaps	xmm7, [eax]
	movaps	xmm6, [ebx]

	ret
endp

;==============================================================================
;      Function : MixColumns
;		  This Function is at the core of the algorithm, it performs
;		  some polynom based operations on the columns of the state
;
;		  XMM register are used here to provide a constant time implemen
;		  tation of this operation
;==============================================================================
proc MixColumns
	; Preparation des matrices 80808080 de masquage
	; xmm6 <= 00 si il faut renormaliser (FF sinon)
	movaps	xmm5, xmm7

	; Chargement de l'etat dans des registres annexes
	; State => xmm1, xmm2
	movups	xmm1, xmm0
	movups	xmm2, xmm1

	;debug : 
	;mov edx, [v1]

	; Calcul de etat * {02}
	; Teste la necessite de la renormalisation

	; xmm7 > xmm2 ?  xmm6 = { 00 } : { 1B }
	pand	xmm2, xmm5
	movaps	xmm4, xmm7

	pcmpeqb	xmm5, xmm2

	;movups	xmm2, [eax]
	pand	xmm5, xmm6

	; Realisation du decalage avant renormalisation 
	; par le polynome 1b
	pslld	xmm1, 01h

	; Preparation du masque pour eliminer les bits
	; decales "en trop"
	psrlw	xmm4, 07h

	; Application du masque (fin du left shift)
	pandn	xmm4, xmm1

	; A cet stade xmm0 : etat courant
	; xmm1 : disponible
	; xmm2 : etat courant
	; xmm4 : etat decale vers la gauche
	; xmm5 : matrice des xor

	; ici : xmm5 = matrice de {1b}
	; Realisation du xor
	movaps	xmm2, xmm4
	pxor	xmm2, xmm5

	; Etat * {02} Calculé

	; On passe a l'operation de melange
	; Ici : xmm0 = state
	; et xmm2 = state * {02}

	; Reste à calculer : bij = {02} * aij (+) {03} ai+1,j (+) ai+2,j (+) ai+3,j 
	; On utilise les régistres comme suit :

	; XMM0 : State (xmm0)
	; XMM1 : State(i+2) (xmm0)
	; XMM2 : State * {02} (xmm2)
	; XMM3 : State * {02} (i+1) (xmm2)
	; XMM4 : State(i+1+2) (xmm0)
	; XMM5 : State(i+1) (xmm0)

	; decalage x3 = 93
	; decalage x2 = 4e
	; decalage x1 = 39

	pshufd	xmm4, xmm0, 093h	
	pshufd	xmm3, xmm2, 039h
	pshufd	xmm1, xmm0, 04eh
	pxor	xmm2, xmm3
	pxor	xmm1, xmm4
	pshufd	xmm5, xmm0, 039h

	movaps	xmm0, xmm2

	pxor	xmm1, xmm5
	pxor	xmm0, xmm1

	; debug : dstate 	xmm0

	ret
endp


;==============================================================================
;      Function : ShiftRows : Performs Cyclic Permutation on rows
;				@Deprecated since this permutation is performed
;				during the SubByte Step
;==============================================================================
proc ShiftRows_SSSE3
	lea		eax 	, [shiftable]
	movaps	xmm1 	, [eax]
	
	pshufb	xmm0, xmm1
	ret
endp

; Macro instuction lire 32bits
macro load32 dest, xmmreg, imm {
	
	push 	ebx 				; Sauve ebx
	pextrw 	ebx, xmmreg, imm+1  ; Extrait les 16bits de poids fort
	shl 	ebx, 16 			; Les decale en poids fort dans ebx
	pextrw 	dest, xmmreg, imm 	; 16bits de poids faible
	or 		dest, ebx 			; Mix des deux
	pop 	ebx 				; Restauration ebx

}

macro store32 xmmreg, src, imm {
	pinsrw 	xmmreg, src, imm
	shr 	src, 16
	pinsrw 	xmmreg, src, imm+1
}

macro load_rol_extract xmmreg, imm {
	load32 	eax, xmmreg, 2*imm
	rol 	eax, 8*imm
	store32 xmmreg, eax, 2*imm
}

; Adaptation pour tous processeurs: on declae successivement dans eax avant de tourner
proc ShiftRows
	; On copie xmm0 dans un autre registre
	movaps 	xmm1, xmm0
 	
	load_rol_extract xmm1,1	
	load_rol_extract xmm1,2	
	load_rol_extract xmm1,3	

	movaps 	xmm0, xmm1
	
	ret

endp
	

;==============================================================================
;      DumpState : Extract current state value into Memory
;==============================================================================
proc DumpState, v1
	mov	edx, [v1]
	movups	[edx], xmm0

    ret
endp

;==============================================================================
;      SetState : Load state value from memory
;==============================================================================
proc SetState, v1
	mov	eax, [v1]
	movups	xmm0, [eax]

    ret
endp

;==============================================================================
;      Example Test Function
;==============================================================================
proc AsmTest, v1, v2, v3

	mov	eax, [v1]
	mov	ebx, [v2]

    add eax, ebx

    mov ebx, [v3]
    mov [ebx], eax

;	inc eax

    ret
endp

section '.data' writeable align 16
; Acces : [matable+n*octets]

; Table des 4 vecteurs de rotation. Sera chargée dans cet ordre.
; Donc le dernier vecteur ici sera chergé en quatrieme dword de xmm0.
; Par contre chaque dword indépendamment est considéré en little indian.
shiftable  dd	03020100h
	   dd	06050407h
	   dd	09080b0ah
	   dd	0c0f0e0dh

ip1_table  dd	07060504h
	   dd	0b0a0908h	
	   dd	0f0e0d0ch	
	   dd	03020100h	

ip2_table  dd	0b0a0908h	
	   dd	0f0e0d0ch	
	   dd	03020100h	
	   dd	07060504h

; Table de comparaison pour detecter la sortie
; d'un bit de l'octet de base
mixtable1  db	80h, 80h, 80h, 80h
	   db	80h, 80h, 80h, 80h
	   db	80h, 80h, 80h, 80h
	   db	80h, 80h, 80h, 80h

; Table contenant ~{1b} pour renormalisation
; du polynome
mixtable2  db	01bh, 01bh, 01bh, 01bh
	   db	01bh, 01bh, 01bh, 01bh
	   db	01bh, 01bh, 01bh, 01bh
	   db	01bh, 01bh, 01bh, 01bh

; Table contenant un 1 sur les positions de la matrice
; de calcul où l'on doit 

ones	   db	0ffh, 0ffh, 0ffh, 0ffh	
	   db	0ffh, 0ffh, 0ffh, 0ffh	
	   db	0ffh, 0ffh, 0ffh, 0ffh	
	   db	0ffh, 0ffh, 0ffh, 0ffh	

; Table de masquage
mask1	  db	00h, 00h, 00h, 0ffh
	  db	00h, 00h, 00h, 0ffh
	  db	00h, 00h, 00h, 0ffh
	  db	00h, 00h, 00h, 0ffh

msg db 'Hello world!',0xA
msg_size = $-msg
