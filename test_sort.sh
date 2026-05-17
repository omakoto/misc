export LC_ALL=C
{
    echo -e "A\n1\0B\n2\0C\n3\0"
} | sort -z > a.txt
{
    echo -e "B\n2\0C\n3\0D\n4\0"
} | sort -z > b.txt
comm -z -13 a.txt b.txt
