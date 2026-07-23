make:
	rgbasm -o syllabus.o syllabus.asm
	rgblink -n syllabus.sym -o syllabus.gb syllabus.o
	rgbfix -v -p 0xFF syllabus.gb

run:
	open syllabus.gb