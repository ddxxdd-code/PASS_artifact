# Makefile for compiling poll_simul.c

# Compiler to use
CC = gcc

# Compiler flags:
CFLAGS = -pthread -lm -O2 -march=native -Wno-unused-result

# Name of the target executable
TARGET = poll_simul

# Name of the source file
SRCS = poll_simul.c

# Default target: Build the executable
# This is the rule that runs when you just type 'make'
all: $(TARGET)

# Rule to link the executable
$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

# Rule to clean up built files
# Type 'make clean' to run this
clean:
	rm -f $(TARGET)

# Declare 'all' and 'clean' as phony targets, meaning they don't represent actual files
.PHONY: all clean
