# Stage 1: Build Stage
FROM node:26-alpine AS builder

WORKDIR /app

# Copy package files and install ALL dependencies
COPY package*.json ./
RUN npm install

# Copy source code
COPY . .

# Run build steps
# setup-websocket.js downloads socket.io.js to public/
RUN node setup-websocket.js
RUN npm run build:css:prod
RUN npm run copy-assets

# Stage 2: Production Stage
FROM node:26-alpine

WORKDIR /app

# docker CLI + compose plugin, used to manage per-instance docker-compose.yml files
RUN apk add --no-cache docker-cli docker-cli-compose

# Copy only production dependencies
COPY package*.json ./
RUN npm install --omit=dev

# Copy application source and built assets from builder
COPY --from=builder /app/server.js ./
COPY --from=builder /app/public ./public
# Create temp and logs directories
RUN mkdir -p temp/addon-uploads temp/uploads logs

# Expose port
EXPOSE 3001

# Set environment variables
ENV DATA_DIR=/app/minecraft-data
ENV NODE_ENV=production

# Run the application
CMD ["node", "server.js"]
