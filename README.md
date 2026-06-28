# Koboldcpp v1.116 Release — Build Script e Istruzioni

## Panoramica

Questo progetto fornisce script di build automatizzati per Koboldcpp v1.116 ottimizzati per diverse architetture GPU NVIDIA. Include build dedicate per Tesla P40 (sm_61) e RTX 3050 (sm_86), con supporto per benchmark manuale e verifica della build.

## Obiettivo

Creare build di Koboldcpp v1.116 ottimizzate per:
- **Tesla P40** (Compute Capability 6.1, 24 GB VRAM)
- **RTX 3050** (Compute Capability 8.6, 8 GB VRAM)

Permettere benchmark comparativi di performance (tok/s) e utilizzo VRAM tra le due GPU.

## Componenti

### Script di Build

**build_koboldcpp.sh** — Script interattivo per generare build separate per ogni GPU targetato.

**Funzionalità:**
- Detect automatica GPU disponibili con `nvidia-smi`
- Menu interattivo per selezionare GPU target
- Build parallele con `make -j$(nproc)`
- Output in directory `build_0/` (P40) o `build_1/` (RTX 3050)

**Uso:**
```bash
chmod +x build_koboldcpp.sh
./build_koboldcpp.sh
```

**Opzioni menu:**
- `1` — Build solo per Tesla P40
- `2` — Build solo per RTX 3050
- `3` — Build per entrambe le GPU
- `4` — Esci

### Flag CUDA Utilizzate

| GPU | Compute Capability | Flag CUDA | VRAM |
|-----|-------------------|-----------|------|
| Tesla P40 | sm_61 | `-DCMAKE_CUDA_ARCHITECTURES="61"` | 24 GB |
| RTX 3050 | sm_86 | `-DCMAKE_CUDA_ARCHITECTURES="86"` | 8 GB |

**Variabili di build:**
- `GGML_CUDA=ON` — Abilita supporto CUDA
- `CMAKE_BUILD_TYPE=Release` — Build ottimizzata per produzione
- `BUILD_SHARED_LIBS=OFF` — Build static library
- `GGML_CUDA_FAQS=ON` — Abilita documentazione CUDA

### Script di Test

**test_manuali.sh** — Script automatizzato per benchmark di performance.

**Funzionalità:**
- Test multipli build (P40, RTX 3050, entrambe)
- Misurazione tok/s e VRAM utilizzata
- Output in formato leggibile con `jq` e `bc`

**Uso:**
```bash
chmod +x test_manuali.sh
./test_manuali.sh all      # Test tutte le build
./test_manuali.sh 0        # Test solo P40
./test_manuali.sh 1        # Test solo RTX 3050
```

## Istruzioni di Build

### Prerequisiti

1. Koboldcpp v1.116 sorgente scaricato ed estratto
2. NVIDIA driver installati (compatibili CUDA 12.x)
3. CUDA toolkit installato
4. Dipendenze build: cmake, make, gcc/g++
5. `jq` e `bc` per benchmark script

### Build con Script

```bash
# Rendi eseguibile lo script
chmod +x build_koboldcpp.sh

# Esegui lo script
./build_koboldcpp.sh

# Seleziona opzione desiderata dal menu
```

### Build Manuale (Opzionale)

**Tesla P40:**
```bash
mkdir build_p40 && cd build_p40
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA_FAQS=ON
make -j$(nproc)
```

**RTX 3050:**
```bash
mkdir build_3050 && cd build_3050
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA_FAQS=ON
make -j$(nproc)
```

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

## Istruzioni Test Manuali

Per testare le build manualmente:

1. Avvia il server Koboldcpp:
   ```bash
   ./build_0/koboldcpp --model /path/to/model.gguf --port 8080 --host 127.0.0.1 --ctx-size 2048 --n-gpu-layers 99
   ```

2. Esegui richiesta benchmark:
   ```bash
   curl -s -X POST "http://127.0.0.1:8080/v1/completions" \
     -H "Content-Type: application/json" \
     -d '{
       "prompt": "Explain the theory of relativity in detail.",
       "max_tokens": 128,
       "temperature": 0.7,
       "top_p": 0.9,
       "stream": false
     }' | jq '.'
   ```

3. Monitora VRAM:
   ```bash
   watch -n 0.5 "nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i 0"
   ```

## Troubleshooting

### Errore "CUDA not found"
- Verifica installazione CUDA: `nvcc --version`
- Verifica driver: `nvidia-smi`

### Errore "sm_61 not supported"
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

## Documentazione

- **BUILD_FLAGS.md** — Dettagli completi flag CUDA e variabili di build
- **TEST_INSTRUCTIONS.md** — Istruzioni complete per benchmark manuale
- **PROGRESS.md** — Stato avanzamento e fasi completate
- **TASK.md** — Descrizione originale del task
