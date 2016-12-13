#include <unistd.h>
#include <stdio.h>

int
main(int argc, char *argv[]) {
	char opt;
	while ((opt = getopt(argc, argv, "o:")) != -1) {
		switch (opt) {
		case 'o' : {
			FILE *f = fopen(optarg, "wb");
			if (f == NULL)
				return 1;
			int i;
			for (i=0;i<argc;i++) {
				fprintf(f, "%s ", argv[i]);
			}
			fclose(f);
			return 0;
		}
		}
	}
	return 0;
}
