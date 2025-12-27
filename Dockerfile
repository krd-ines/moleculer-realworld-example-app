FROM node:6

RUN mkdir /app
WORKDIR /app

COPY package.json .

RUN npm install --production
RUN npm install nats@1.4.12 --save

COPY . .

CMD ["npm", "start"]