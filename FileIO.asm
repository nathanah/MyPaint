	;===================================================================================================================;
	;	Authors: Erik Olson, Nathan Hoffman, Ruvim Lashchuk, and Seth Murdoch											;	
	;	Date: 2017-12-02																								;
	;																													;
	;	This program takes "inFile.bmp" from its directory and manipulates the RGB values of each pixel in the image.	;
	;		The code isn't dynamic. We hardcoded it to only work with 24-bit bmp file types.							;
	;																													;
	;	Relevant links:																									;
	;		CreateFile:																									;
	;			https://msdn.microsoft.com/en-us/library/windows/desktop/aa363858(v=vs.85).aspx							;
	;		ReadFile:																									;
	;			https://msdn.microsoft.com/en-us/library/windows/desktop/aa365467(v=vs.85).aspx							;
	;		WriteFile:																									;
	;			https://msdn.microsoft.com/en-us/library/windows/desktop/aa365747(v=vs.85).aspx							;
	;		ExitProcess:																								;
	;			https://msdn.microsoft.com/en-us/library/windows/desktop/ms682658(v=vs.85).aspx							;
	;		BMP Format:																									;
	;			http://www.fastgraph.com/help/bmp_header_format.html													;
	;			https://upload.wikimedia.org/wikipedia/commons/c/c4/BMPfileFormat.png									;
	;			http://www.daubnet.com/en/file-format-bmp																;
	;===================================================================================================================;
	
	.486                                    ; create 32 bit code
    .model flat, stdcall                    ; 32 bit memory model
    option casemap :none                    ; case sensitive
 
    include \masm32\include\windows.inc     ; Settup for libraries and includes
    include \masm32\macros\macros.asm       ; MASM support macros

	include \masm32\include\masm32.inc
    include \masm32\include\gdi32.inc
    include \masm32\include\user32.inc
    include \masm32\include\kernel32.inc	; Responsible for windows api
	
	includelib \masm32\lib\masm32.lib
    includelib \masm32\lib\gdi32.lib
    includelib \masm32\lib\user32.lib
    includelib \masm32\lib\kernel32.lib


	;=======================================================================================;
	;		Handling 24bit bmp files														;
	;		Header: 54 bytes																;
	;		Padding: Each row is padded to be a multiple of 4 bytes. Range = 0 to 3 bytes.	;
	;=======================================================================================;

    .data
    	
		hFile				DWORD	?				; holds handle for in file
		hFileOut			DWORD	?				; holds handle for out file
		
		inFile				BYTE	"inFile.bmp", 0
		outFile				BYTE	"outFile_Tree_().bmp", 0

		readBytes			DWORD	?				; stores how many bytes were read from file
		writtenBytes		DWORD	?				; Stores how many bytes were written to file
		
		pixelArray			BYTE	766800 DUP (?)	
		pixelArray_Size		DWORD	?				; Dynamic element.  Parsed from bmp header.
		iPixel				BYTE	?, ?, ?			; Individial BRG pixel that will be scaled and stored. Short for "Individual Pixel".
		
		bmpHeader			BYTE	54 DUP (?)		; Standard bmp file header size
		bmpHeader_Size		DWORD	36h				; To bypass image header
		
		xPixels				DWORD	?				; Offset of 18 bytes
		yPixels				DWORD	?				; Offset of 22 bytes
		padBytes			DWORD	?				; (4 - xPixels % 4) % 4
		stockPadding		DWORD	?				
		
		index				DWORD	?				; = (row * xPixel + column) * 3 + row * padding
		rowIndex			DWORD	?				; Row iterator
		columnIndex			DWORD	?				; Column iterator

		redDarkenFactor		DWORD	100
		greenDarkenFactor	DWORD	100
		blueDarkenFactor	DWORD	100

		just100				DWORD	100



    .code                       ; Tell MASM where the code starts

; >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

start:                          ; The CODE entry point to the program

    call main                   ; branch to the "main" procedure

    exit

; >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

colorShift proc
	;=======================================================================;
	;		Using CreateFile to get File handle for our output file			;	
	;=======================================================================;
    ; CreateFile(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile)
	invoke	CreateFile, offset outFile, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
	mov		hFileOut, eax					; Move file handle from common register for file to output image



	;===============================================================================;
	;		Using CreateFile to get File handle for the file we will be reading		;
	;===============================================================================;
	; CreateFile(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile)
	invoke	CreateFile, offset inFile, GENERIC_READ, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_READONLY, 0
	mov		hFile, eax						; Move file handle from common register for file to read image



	;===================================================================================================================;
	;		Reading file data.																							;
	;			Step 1:	parsing file header for file information														;
	;			step 2:	reading the rest of the information separately to store only the pixel content in pixelArray.	;
	;					See fastgraph.com/help/bmp_header_format.html													;
	;===================================================================================================================;
	; ReadFile(hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesToRead, lpOverlapped)
	invoke	ReadFile, hFile, offset bmpHeader, bmpHeader_Size, offset readBytes, 0
	
	; DWORD because the width value is stored in four bytes
	mov		eax, DWORD PTR bmpHeader[22]	; +22 corresponds to height in pixels			
	mov		yPixels, eax					; Moving double word in eax into yPixels
	
	mov		eax, DWORD PTR bmpHeader[18]	; +18 corresponds to width in pixels
	mov		xPixels, eax					; Moving double word in eax into yPixels



	;===================================;
	;		Calculating Padding			;
	;===================================;
	; Finding padding of the rows
	xor		edx, edx						; Clearing EDX register to prevent overflow and undesired data.
	; eax currently holds xPixels
	mov		ebx, 4				
	div		ebx								; xPixels % 4
	sub		ebx, edx						; 4 - (xPixels % 4)
	mov		eax, ebx						
	mov		ebx, 4							
	div		ebx								; (4 - (xPixels % 4)) % 4
	mov		padBytes, edx					; edx holds remainder



	;=======================================;
	;	Calculating Total Pixel Memory		;
	;=======================================;
	mov		edx, DWORD PTR bmpHeader[2]	; +2 corresponds to file size
	sub		edx, bmpHeader_Size				
	mov		pixelArray_Size, edx			; we are only consider the pixel space as file size
    


	;===========================================;
	;		Reading the rest of the file		;
	;===========================================;
	; ReadFile(hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesToRead, lpOverlapped)
	invoke	ReadFile, hFile, offset pixelArray, pixelArray_Size, offset readBytes, 0



	;===================================================================================;
	;		Writing bmp header to file.  The header's information is preserved.			;
	;				The program only manipulates pixel information.						;
	;===================================================================================;
	; WriteFile(hFile, lpBuffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped)
	invoke WriteFile, hFileOut, offset bmpHeader, 54, offset writtenBytes, 0



	;===================================================================================;
	;		Looping through the Pixel Array space and manipulating every RGB pixel.		;
	;===================================================================================;
	xor		ecx, ecx						; Row Counter: Initialiaze to 0
	mov		rowIndex, 0						; Range: 0 to (yPixels - 1)			= Rows
	
	xor		edx, edx						; Column Counter: Initialize to 0
	mov		columnIndex, 0					; Domain: 0 to (xPixels - 1)		= Column



RowLoop:
	mov columnIndex, 0						; Reseting column index for new row

ColumnLoop:
	;=======================================================================================================;
	;		Index = ( Pixel.Row * Row.Width + Pixel.Column ) * Pixel.Size + Pixel.Row * Row.Padding			;
	;=======================================================================================================;
	xor		eax, eax						; Initialize Registers to clear old data
	xor		ebx, ebx
	
	; 
	mov		eax, rowIndex					; row
	mul		xPixels							; row * xPixels
	add		eax, columnIndex				; row * xPixels + column
	imul	eax, 3							; (row * xPixels + column) * 3			; In 24-bit bmp: Pixel.Size = 3
	mov		ebx, padBytes					; padBytes
	imul	ebx, rowIndex					; padBytes * row

	; Complete Index
	add		eax, ebx						; [(row * xPixels + column) * 3] + [padBytes * row]

	mov		index, eax
	xor		eax, eax


	;===========================================================;
	;			Retrieving the bit RGB24 values					;
	;				3 Bytes: Red, Green Blue					;
	;		pixelArray starts at bottom left of the image		;
	;	  In sets of three bytes, the color order is: BGR		;
	;===========================================================;
	lea		ecx, pixelArray					; load effective address of pixelArray					
	add		ecx, index						; move to address of the pixel of interest


	; Instruction operands must be the same size so we're using lower registers
	mov		al, BYTE PTR [ecx]				; Moving Blue value to ebx		
	imul	eax, blueDarkenFactor
	div		just100
	mov		iPixel, al
	xor		eax, eax
	xor		edx, edx

	mov		al, BYTE PTR [ecx + 1]			; Moving Green value to ebx
	imul	eax, greenDarkenFactor
	div		just100
	mov		iPixel[1], al
	xor		eax, eax
	xor		edx, edx

	mov		al, BYTE PTR [ecx + 2]			; Moving Red value to ebx
	imul	eax, redDarkenFactor
	div		just100
	mov		iPixel[2], al
	xor		eax, eax
	xor		edx, edx

	
	;=======================================;
	;		Saving pixel to memory			;
	;=======================================;
	; WriteFile(hFile, lpBuffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped)
	invoke WriteFile, hFileOut, offset iPixel, 3, offset writtenBytes, 0

	; increment ColumnCounter
	inc		columnIndex
	mov		edx, columnIndex
	cmp		edx, xPixels
	jl		ColumnLoop
endColumnLoop:

	; WriteFile(hFile, lpBuffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped)
	invoke WriteFile, hFileOut, offset stockPadding, padBytes, offset writtenBytes, 0

	inc		rowIndex
	mov		edx, rowIndex
	cmp		edx, yPixels
	jl		RowLoop

endRowLoop:
	
	xor		eax, eax
	xor		ebx, ebx
	xor		ecx, ecx
	xor		edx, edx
	invoke ExitProcess, 0

	ret
colorShift endp

; >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

main proc
	; mov		al, 32h
	; mov		outFile[7], al

	mov		redDarkenFactor, 8
	mov		greenDarkenFactor, 53
	mov		blueDarkenFactor, 2
	invoke colorShift

main endp

; >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

end start                       ; Tell MASM where the program ends