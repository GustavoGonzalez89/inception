NAME = inception

COMPOSE = docker compose
FILE = -f ./srcs/docker-compose.yml

all: build 

build:
	@mkdir -p /home/gustgonz/data/wordpress
	@mkdir -p /home/gustgonz/data/mariadb
	@$(COMPOSE) $(FILE) up -d --build

#stop containers and removes all 
down: 
	@$(COMPOSE) $(FILE) down -v
#force stop service containers
kill:
	@$(COMPOSE) $(FILE)  kill 

log:
	@$(COMPOSE) $(FILE)  logs

clean:
	@$(COMPOSE) $(FILE)  down -v 

fclean: clean
	@docker system prune -a -f 
	@docker volume prune -f 
	@docker network prune -f 

restart: fclean all 

.PHONY: kill build log down clean restart 
