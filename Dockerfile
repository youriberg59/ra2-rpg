FROM node:22-alpine

WORKDIR /app

COPY server/package.json ./server/package.json
RUN cd server && npm install --omit=dev

COPY server ./server
COPY client ./client
COPY content ./content

WORKDIR /app/server

EXPOSE 8080

CMD ["node", "src/index.js"]
