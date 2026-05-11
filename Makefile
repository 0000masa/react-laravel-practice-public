up :
	docker compose --env-file ./environment/laravel/.env up -d

down :
	docker compose --env-file ./environment/laravel/.env down

make react-build:
	docker compose exec react npm run build
