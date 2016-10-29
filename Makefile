SRC = $(filter-out index.md,$(wildcard *.md))
HTML = $(SRC:.md=.html)
LAYOUT = $(wildcard layout/*.html)
RM = rm
PANDOC = pandoc
SQLITE = sqlite3

.PHONY: all clean web

all: web

clean:
	$(RM) articles.sql articles.db
	$(RM) index.md index.html
	$(RM) $(HTML)

web: index.html $(HTML)

articles.sql: $(SRC)
	echo "DROP TABLE IF EXISTS articles;" > $@
	echo "DROP TABLE IF EXISTS keywords;" >> $@
	echo "CREATE TABLE articles (path PRIMARY KEY, title, date);" >> $@
	echo "CREATE TABLE keywords (path, keyword, PRIMARY KEY(path, keyword));" >> $@
	$(foreach f,$^,$(PANDOC) --template=layout/sql.html --metadata=path:$(f:.md=.html) $(f) >> $@;)

articles.db: articles.sql
	cat $< | $(SQLITE) $@

index.md: articles.db
	echo "# Hi, I'm Ichiban" > $@
	echo "" >> $@
	echo "I'm a Software Developer in Tokyo, Japan." >> $@
	echo "" >> $@
	echo "## Recent Posts" >> $@
	$(SQLITE) $< "SELECT printf('- [%s](%s) (%s)', title, path, date) FROM articles WHERE date <> '' ORDER BY date DESC LIMIT 4;" >> $@
	echo "" >> $@
	$(SQLITE) $< "SELECT printf('## %s' || char(10) || '%s' || char(10), k.keyword, group_concat(printf('- [%s](%s)', a.title, a.path), char(10))) FROM keywords k LEFT OUTER JOIN articles a on k.path = a.path GROUP BY k.keyword ORDER BY COUNT(*) DESC;" >> $@

%.html: %.md $(LAYOUT)
	$(PANDOC) \
	--output $@ \
	--template=layout/article.html \
	--css=css/normalize.css \
	--css=css/common.css \
	--mathjax \
	$<
