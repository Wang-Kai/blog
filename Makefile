.PHONY: blog upload

blog:
	rm -fr ./public
	hugo
	rm -fr /tmp/public && mv public /tmp

upload:
	cd /tmp/public && \
	git init && \
	git remote add origin git@github.com:Wang-Kai/Wang-Kai.github.io.git  && \
	git add .  && \
	git commit -m "Blog update at $(shell date)"  && \
	git push -f origin main