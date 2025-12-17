# Makefile for hot_cold

CC      := gcc
CFLAGS  := -std=gnu11 -O2 -Wall -Wextra
LDFLAGS := -lnuma

TARGET  := hot_cold
SRC     := hot_cold.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(TARGET)
