build:
	odin build .

debug:
	odin build . -debug -sanitize:address

run:
	make build
	./odinlox

test:
	odin test .
