CXX := g++
CXXFLAGS := -shared -fPIC -O2 -std=c++23 -Wall -Wextra -Wno-unused-parameter $(shell pkg-config --cflags hyprland)

TARGET := hypr-showdesktop.so

all: $(TARGET)

$(TARGET): main.cpp
	$(CXX) $(CXXFLAGS) main.cpp -o $(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all clean
