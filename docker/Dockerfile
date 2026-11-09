# Etapa de compilación
FROM rust:1-bookworm AS builder

# Replica la estructura del repo para que include_str!("../../../../database/...") resuelva
WORKDIR /workspace/Backend/credito_backend

# Dependencias
COPY Backend/credito_backend/Cargo.toml Backend/credito_backend/Cargo.lock ./

# Código fuente
COPY Backend/credito_backend/src ./src

# Archivos que el código incluye en tiempo de compilación
COPY database /workspace/database

# Compilar backend
RUN cargo build --release --locked

# Etapa final
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/Backend/credito_backend/target/release/credito_backend /app/credito_backend

EXPOSE 3000

CMD ["/app/credito_backend"]