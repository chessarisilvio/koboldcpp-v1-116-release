# Koboldcpp v1.116 — Build Flags e Istruzioni

## Overview

Questo documento descrive gli script di build per Koboldcpp v1.116 ottimizzati per:
- **Tesla P40** (sm_61, 24 GB VRAM)
- **RTX 3050** (sm_86, 8 GB VRAM)

## Script di Build

### build_koboldcpp.sh

Script interattivo che:
1. Detecta le GPU disponibili con `nvidia-smi`
2. Permette di scegliere quale GPU targetare
3. Genera build separate per ogni GPU scelta
4. Salva output in directory `build_0/` (P40) o `build_1/` (RTX 3050)

**Uso:**
```bash
chmod +x build_koboldcpp.sh
./build_koboldcpp.sh
```

**Opzioni menu:**
- `1` — Build solo per P40
- `2` — Build solo per RTX 3050
- `3` — Build per entrambe le GPU
- `4` — Esci

## Flag CUDA Utilizzati

### Tesla P40 (sm_61)
```bash
-DCMAKE_CUDA_ARCHITECTURES="61"
```
- Target: Compute Capability 6.1
- VRAM: 24 GB
- Ottimizzato per tensor core legacy (non presenti su P40)

### RTX 3050 (sm_86)
```bash
-DCMAKE_CUDA_ARCHITECTURES="86"
```
- Target: Compute Capability 8.6
- VRAM: 8 GB
- Ottimizzato per tensor core Ampere (RTX 30/40 series)

## Variabili di Build

| Variabile | Valore | Descrizione |
|-----------|--------|-------------|
| `GGML_CUDA` | ON | Abilita supporto CUDA |
| `CMAKE_BUILD_TYPE` | Release | Build ottimizzata per produzione |
| `BUILD_SHARED_LIBS` | OFF | Build static library (compatibile con KoboldAI) |
| `GGML_CUDA_FAQS` | ON | Abilita FAQ e documentazione CUDA |

## VRAM Split (Multi-GPU)

Per utilizzare P40 + RTX 3050 insieme:

1. **Build per entrambe le GPU:**
   ```bash
   ./build_koboldcpp.sh
   # Seleziona opzione 3
   ```

2. **Configura VRAM split:**
   ```bash
   export CUDA_VISIBLE_DEVICES=0,1  # P40 (0) + RTX 3050 (1)
   export CUDA_DEVICE_MAX_CONNECTIONS=1
   ```

3. **Esegui KoboldAI con split:**
   ```bash
   koboldcpp --model modello.gguf --context-size 4096 --gpu-layers 35
   ```

   - **P40** gestisce i layer pesanti (GPU 0)
   - **RTX 3050** gestisce layer leggeri (GPU 1)
   - VRAM totale: 24 GB + 8 GB = 32 GB

## Verifica Build

Dopo la build, verificare:

```bash
# Controlla binario
ls -lh build_0/koboldcpp
ls -lh build_1/koboldcpp

# Test esecuzione (senza modello)
build_0/koboldcpp --help
build_1/koboldcpp --help
```

## Troubleshooting

### Errore: "CUDA not found"
- Verifica installazione CUDA: `nvcc --version`
- Verifica driver: `nvidia-smi`

### Errore: "sm_61 not supported"
- GPU non è una P40 (o driver obsoleto)
- Controlla `nvidia-smi --query-gpu=name --format=csv,noheader`

### Build lenta
- Usa `make -j$(nproc)` per parallelizzare
- Build P40 richiede ~10-15 min, RTX 3050 ~5-8 min

### VRAM insufficiente
- Riduci `--context-size` o `--gpu-layers`
- RTX 3050 (8 GB): max ~4k context con 35 layers
- P40 (24 GB): max ~8k context con 35 layers

## Note v1.116

- Verificare changelog per eventuali fix CUDA specifici
- Se presente fix per sm_61, questo script lo include automaticamente
- Se presente miglioramento VRAM split, usare opzione 3 per entrambe le GPU
