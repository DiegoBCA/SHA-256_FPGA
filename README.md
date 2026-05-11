# SHA-256_FPGA
# SHA-256 en FPGA con Verificación de Integridad vía UART

Implementación en Verilog de un acelerador hardware SHA-256, desplegado en dos tarjetas **DE10-Lite (Intel MAX 10)** que se comunican mediante **UART** para verificar la integridad de datos en tiempo real.

---

## 📋 Descripción General

Este proyecto implementa el algoritmo de hash criptográfico **SHA-256** directamente en lógica programable (FPGA), sin uso de procesador externo. El sistema está dividido en dos FPGAs:

| FPGA | Rol | Módulo Top |
|------|-----|-----------|
| **Transmisor (TX)** | Calcula SHA-256 del dato ingresado por los switches y lo envía por UART | `fpga_tx_top.v` |
| **Receptor (RX)** | Recibe el dato + hash, recalcula el SHA-256 y verifica la integridad | `fpga_rx_top.v` |

El flujo completo permite comprobar que un dato de 8 bits no fue alterado en la transmisión serial, encendiendo un **LED verde** si la verificación es exitosa o un **LED rojo** si hay error.

---

## 🗂️ Estructura del Proyecto

```
sha256/
├── sha256_core.v     # Núcleo SHA-256 (máquina de estados, 67 ciclos)
├── uart_tx.v         # Transmisor UART 8N1
├── uart_rx.v         # Receptor UART 8N1
├── fpga_tx_top.v     # Top-level FPGA Transmisor
└── fpga_rx_top.v     # Top-level FPGA Receptor
```

---

## ⚙️ Arquitectura

### Núcleo SHA-256 (`sha256_core.v`)

Implementa el estándar **FIPS 180-4** para mensajes de 32 bits con las siguientes características:

- **Padding automático**: El módulo genera el bloque de 512 bits conforme al estándar SHA-256 (dato de 32 bits + bit `1` + ceros + longitud de 64 bits).
- **Ventana deslizante de 16 palabras**: Optimiza el uso de registros evitando almacenar las 64 palabras del mensaje schedule completo.
- **67 ciclos de cómputo**: 1 ciclo `LOAD` + 64 rondas de compresión + 1 ciclo `DONE`.
- **Máquina de estados de 4 estados**: `IDLE → LOAD → RUN → DONE`.

```
Entradas:  clk, rst, start, data_in[31:0]
Salidas:   hash_out[255:0], done
```

**Funciones SHA-256 implementadas:**

| Función | Descripción |
|---------|-------------|
| `SIG0` | Σ₀(a) = ROTR²(a) ⊕ ROTR¹³(a) ⊕ ROTR²²(a) |
| `SIG1` | Σ₁(e) = ROTR⁶(e) ⊕ ROTR¹¹(e) ⊕ ROTR²⁵(e) |
| `Ch`   | Choice: (e & f) ⊕ (~e & g) |
| `Maj`  | Majority: (a & b) ⊕ (a & c) ⊕ (b & c) |

---

### Transmisor UART (`uart_tx.v`)

Transmisor **8N1** parametrizable:

- **Parámetros**: `CLK_FREQ` (default 50 MHz) y `BAUD_RATE` (default 115,200 bps).
- Envía los bits **LSB primero**.
- Señal `busy` activa durante toda la transmisión.
- Máquina de estados: `IDLE → START → DATA → STOP`.

---

### Receptor UART (`uart_rx.v`)

Receptor **8N1** parametrizable con doble sincronizador para evitar metaestabilidad:

- Detección de flanco de bajada para el bit de inicio.
- Muestreo en el **centro del bit** (HALF_TICKS).
- Señal `valid` de un pulso al recibir un byte correcto.
- Descarta frames con bit de parada inválido.

---

### FPGA Transmisor Top (`fpga_tx_top.v`)

Flujo de operación al presionar el botón:

```
Botón presionado
    └─► Inicia SHA-256 con dato de los switches (SW[7:0])
            └─► SHA done: empaqueta frame de 33 bytes [dato | hash[255:0]]
                    └─► Transmite byte a byte por UART (115,200 bps)
                            └─► LED_BUSY encendido 0.5 s → IDLE
```

**Detección de botón**: Sincronizador de 3 etapas + detector de flanco de bajada para evitar rebotes.

**Frame de transmisión (33 bytes):**
```
[byte 0]      : Dato original (SW[7:0])
[bytes 1..32] : SHA-256 hash (256 bits, big-endian)
```

---

### FPGA Receptor Top (`fpga_rx_top.v`)

Flujo de operación al recibir un frame completo:

```
Recibe 33 bytes por UART
    └─► Extrae dato[7:0] y hash_recibido[255:0]
            └─► Recalcula SHA-256(dato)
                    └─► Compara hash recalculado vs. hash recibido
                            ├─► Igual  → LED_OK  = 1 ✅
                            └─► Distinto → LED_OK = 0 ❌
```

**Timeout de 40 ms**: Si la recepción se interrumpe, el buffer se reinicia automáticamente para evitar bloqueos.

**Display 7 segmentos (HEX0/HEX1)**: Muestra el contador de bytes recibidos (`rx_count`) en hexadecimal, útil para diagnóstico.

---

## 🔌 Conexiones de Hardware

| Señal | FPGA TX | FPGA RX |
|-------|---------|---------|
| UART TX → RX | `GPIO_OUT[0]` | `GPIO_IN[0]` |
| GND común | GND | GND |
| Reloj | 50 MHz (MAX10_CLK1_50) | 50 MHz (MAX10_CLK1_50) |
| Reset | KEY[0] (activo bajo) | KEY[0] (activo bajo) |
| Dato de entrada | SW[7:0] | — |
| Botón enviar | KEY[1] (activo bajo) | — |
| LED ocupado | LEDR[0] | — |
| LED OK | — | LEDR[0] (verde) |
| LED Error | — | LEDR[1] (rojo) |
| 7-seg diagnóstico | — | HEX0, HEX1 |

---

## 🚀 Síntesis e Implementación

### Requisitos

- **Software**: Intel Quartus Prime (versión Lite o superior)
- **Tarjeta**: DE10-Lite (FPGA Intel MAX 10 — 10M50DAF484C7G)
- **Herramienta de programación**: USB-Blaster

### Pasos

1. Abrir Quartus Prime y crear un nuevo proyecto.
2. Agregar todos los archivos `.v` al proyecto.
3. Seleccionar el dispositivo `10M50DAF484C7G`.
4. Asignar pines según la tabla de conexiones y el Pin Planner de la DE10-Lite.
5. Compilar (`Processing → Start Compilation`).
6. Programar cada FPGA con su archivo `.sof` correspondiente.

---

## 📊 Recursos de Hardware Estimados

| Recurso | Estimado |
|---------|---------|
| LEs (Logic Elements) | ~800–1,200 |
| Registros | ~400–600 |
| Frecuencia máxima | > 50 MHz |
| Latencia SHA-256 | 67 ciclos (~1.34 µs @ 50 MHz) |
| Velocidad UART | 115,200 bps |
| Tiempo de transmisión | ~2.9 ms (33 bytes × 86.8 µs/byte) |

---

## 🧪 Verificación

Para verificar que el hash generado es correcto, se puede usar Python:

```python
import hashlib
import struct

dato = 0x42  # Valor de los switches, ejemplo: SW = 0b01000010

# SHA-256 de un entero de 32 bits (big-endian, mismo padding que el hardware)
data_bytes = struct.pack('>I', dato)  # 4 bytes big-endian
digest = hashlib.sha256(data_bytes).hexdigest()
print(f"SHA-256(0x{dato:08X}) = {digest}")
```


