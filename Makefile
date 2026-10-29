CXX = clang++
CXXFLAGS = -std=c++20 -Wall -Wextra -fobjc-arc -Isrc
LDFLAGS = -framework Cocoa

TARGET = ccast
SRCS = src/main.mm src/ui/window.mm

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CXX) $(CXXFLAGS) $(SRCS) $(LDFLAGS) -o $(TARGET)

clean:
	rm -f $(TARGET) a.out

run: all
	./$(TARGET)

.PHONY: all clean run
