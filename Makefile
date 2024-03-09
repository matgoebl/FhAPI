TARGETS=README.md controls_FhAPI.txt

all: $(TARGETS)

README.md: FHEM/98_FhAPI.pm
	cat $< | grep -A999999 '^=begin html'| tail -n+2 | tac | grep -A999999 '^=end html' | tail -n+2 | tac > README.md 

controls_FhAPI.txt: FHEM/98_FhAPI.pm
	echo "UPD `date +%Y-%m-%d_%H:%M:%S -d @$(shell stat -c %Y $<)` `wc -c < $<` $<" > controls_FhAPI.txt

clean:
	rm -f $(TARGETS)

.PHONY: all clean $(TARGETS)
