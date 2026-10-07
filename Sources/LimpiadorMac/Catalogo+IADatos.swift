import Foundation

// Reglas del área «ia-datos»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// IA, aprendizaje automático y ciencia de datos.
extension Catalogo {
    static let iaDatos: [Regla] = [
        Regla("ollama-brew-registro", "/opt/homebrew/var/log/ollama.log",
              nombre: "Registro del servicio Ollama (Homebrew)",
              detalle: "Archivo de registro del servicio de Ollama instalado con Homebrew; crece sin límite.",
              consecuencia: "Nada: solo es un registro. Solo se ofrece con el servicio de Ollama detenido.")
            .admin().sinPreseleccion().sinArchivosAbiertos().proceso("Ollama", patron: "ollama"),
        Regla("lmstudio-registros-servidor", "~/.lmstudio/server-logs",
              nombre: "Registros del servidor de LM Studio",
              detalle: "Registros del servidor local de LM Studio, uno por día.",
              consecuencia: "Nada: solo son registros. Tus modelos y conversaciones no se tocan.")
            .en(.registros).app("LM Studio", "ai.elementlabs.lmstudio"),
        Regla("lmstudio-registros-servidor-cache", "~/.cache/lm-studio/server-logs",
              nombre: "Registros del servidor de LM Studio",
              detalle: "Registros del servidor local de LM Studio (hogar en ~/.cache/lm-studio).",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).app("LM Studio", "ai.elementlabs.lmstudio"),
        Regla("jan-registros", "~/Library/Application Support/Jan/data/logs",
              nombre: "Registros de Jan",
              detalle: "Registros de la app Jan y de su servidor local.",
              consecuencia: "Nada: solo son registros. Tus conversaciones y modelos no se tocan.")
            .en(.registros).soloSiEstaInstalada().app("Jan", "jan.ai.app"),
        Regla("jan-cache-npx", "~/Library/Application Support/Jan/data/.npx",
              nombre: "Caché de herramientas de Jan (npx)",
              detalle: "Paquetes de Node que Jan descargó para ejecutar sus herramientas (servidores MCP).",
              consecuencia: "Jan los vuelve a descargar la próxima vez que use esas herramientas.")
            .soloSiEstaInstalada().app("Jan", "jan.ai.app"),
        Regla("jan-cache-uvx", "~/Library/Application Support/Jan/data/.uvx",
              nombre: "Caché de herramientas de Jan (uvx)",
              detalle: "Paquetes de Python que Jan descargó para ejecutar sus herramientas (servidores MCP).",
              consecuencia: "Jan los vuelve a descargar la próxima vez que use esas herramientas.")
            .soloSiEstaInstalada().app("Jan", "jan.ai.app"),
        Regla("jan-cache-conversaciones", "~/Library/Application Support/Jan/data/llamacpp/thread-cache",
              nombre: "Memoria rápida de conversaciones de Jan",
              detalle: "Estado guardado del modelo para retomar cada conversación más rápido.",
              consecuencia: "La primera respuesta de cada conversación antigua tardará un poco más. Tus conversaciones no se pierden.")
            .soloSiEstaInstalada().app("Jan", "jan.ai.app"),
        Regla("jan-motores-viejos", "~/Library/Application Support/Jan/data/llamacpp/backends/*",
              nombre: "Versiones viejas del motor de Jan",
              detalle: "Motores llama.cpp que versiones anteriores de Jan descargaron (se conserva el más nuevo).",
              consecuencia: "Las versiones actuales de Jan traen el motor dentro de la app. Si usas una versión vieja de Jan y elegiste otro motor en los ajustes, lo volverá a descargar.")
            .sinPreseleccion().conservando(.versionMasAlta).soloSiEstaInstalada().app("Jan", "jan.ai.app"),
        Regla("gpt4all-modelos-ggml", "~/Library/Application Support/nomic.ai/GPT4All",
              nombre: "Modelos antiguos de GPT4All que ya no funcionan",
              detalle: "Modelos en el formato antiguo .bin, que GPT4All ya no puede abrir.",
              consecuencia: "GPT4All ya no los usa. Si los querías para otro programa, tendrás que descargarlos otra vez.")
            .en(.desarrollo).revisar().archivos("bin").soloSiEstaInstalada().app("GPT4All", "gpt4all"),
        Regla("gpt4all-modelos", "~/Library/Application Support/nomic.ai/GPT4All",
              nombre: "Modelos de GPT4All",
              detalle: "Modelos de IA que descargaste en GPT4All (cada uno ocupa varios GB).",
              consecuencia: "Tendrás que volver a descargar en GPT4All los modelos que quieras usar. Si copiaste tú algún modelo a esta carpeta, también se borrará: guárdalo antes. Tus conversaciones no se tocan.")
            .en(.desarrollo).revisar().archivos("gguf").soloSiEstaInstalada().app("GPT4All", "gpt4all"),
        Regla("gpt4all-python-modelos", "~/.cache/gpt4all",
              nombre: "Modelos de GPT4All para Python",
              detalle: "Modelos que descargó la librería de Python de GPT4All (o el plugin de «llm»).",
              consecuencia: "Se vuelven a descargar la próxima vez que un programa los pida (varios GB).")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("diffusionbee-modelos", "~/.diffusionbee/downloaded_assets",
              nombre: "Modelos de DiffusionBee",
              detalle: "Modelos de Stable Diffusion que DiffusionBee descargó.",
              consecuencia: "DiffusionBee los vuelve a descargar cuando los uses (varios GB). Tus imágenes generadas no se tocan.")
            .en(.desarrollo).revisar().app("DiffusionBee", "com.diffusionbee.diffusionbee"),
        Regla("diffusionbee-entradas", "~/.diffusionbee/inp_images",
              nombre: "Copias de imágenes de entrada de DiffusionBee",
              detalle: "Copias de las imágenes que usaste como punto de partida (imagen a imagen, retoques).",
              consecuencia: "En el historial de DiffusionBee ya no se verán esas imágenes de partida. Si alguna la pegaste desde el portapapeles, esta puede ser la única copia. Las imágenes generadas no se tocan.")
            .revisar().app("DiffusionBee", "com.diffusionbee.diffusionbee"),
        Regla("diffusionbee-depuracion", "~/.diffusionbee/debug_outs",
              nombre: "Salidas de depuración de DiffusionBee",
              detalle: "Archivos de diagnóstico que DiffusionBee guarda en modo depuración.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos.")
            .en(.temporales).app("DiffusionBee", "com.diffusionbee.diffusionbee"),
        Regla("drawthings-descargas-incompletas", "~/Library/Containers/com.liuliu.draw-things/Data/Documents/Downloads",
              nombre: "Descargas a medias de Draw Things",
              detalle: "Modelos que Draw Things empezó a descargar y no terminó.",
              consecuencia: "Si todavía quieres ese modelo, la descarga empezará desde el principio.")
            .en(.temporales).archivos("part").edad(dias: 2).accesoTotal().soloSiEstaInstalada().app("Draw Things", "com.liuliu.draw-things"),
        Regla("drawthings-modelos", "~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models",
              nombre: "Modelos de Draw Things",
              detalle: "Modelos de imagen que descargaste o importaste en Draw Things (suelen ser decenas de GB).",
              consecuencia: "Tendrás que volver a descargar los modelos oficiales desde Draw Things. Los que importaste necesitarán el archivo original, y las LoRA que entrenaste en Draw Things se perderán: guárdalas antes. Tus imágenes no se tocan.")
            .en(.desarrollo).cuidado().archivos("ckpt").accesoTotal().soloSiEstaInstalada().app("Draw Things", "com.liuliu.draw-things"),
        Regla("comfyui-desktop-uv-cache", "~/Documents/ComfyUI/uv-cache",
              nombre: "Caché de paquetes de ComfyUI",
              detalle: "Paquetes de Python que ComfyUI Desktop descargó para instalar su entorno.",
              consecuencia: "Nada: el entorno ya está instalado. Si lo reinstalas, los vuelve a descargar.")
            .en(.desarrollo).sinPreseleccion().app("ComfyUI", "com.todesktop.241012ess7yxs0e"),
        Regla("invokeai-descargas", "~/invokeai/models/.download_cache",
              nombre: "Modelos auxiliares de InvokeAI",
              detalle: "Modelos que InvokeAI descarga solo cuando los necesita (detectores, preprocesadores).",
              consecuencia: "InvokeAI los vuelve a descargar la próxima vez que los use.")
            .en(.desarrollo).revisar().app("Invoke"),
        Regla("pinokio-registros", "~/pinokio/logs",
              nombre: "Registros de Pinokio",
              detalle: "Registros de las apps de IA que instalaste y ejecutaste con Pinokio.",
              consecuencia: "Nada: solo son registros. Tus apps y modelos no se tocan.")
            .en(.registros).app("Pinokio", "computer.pinokio"),
        Regla("pinokio-caches", "~/pinokio/cache/*_CACHE*",
              nombre: "Cachés de descarga de Pinokio",
              detalle: "Paquetes de pip, uv y Homebrew que las apps de Pinokio descargaron al instalarse.",
              consecuencia: "Nada: las apps ya están instaladas. Si reinstalas alguna, vuelve a descargar lo que necesite.")
            .en(.desarrollo).excepto("XDG_CACHE_HOME").app("Pinokio", "computer.pinokio"),
        Regla("pinokio-cache-xdg", "~/pinokio/cache/XDG_CACHE_HOME",
              nombre: "Caché general de las apps de Pinokio",
              detalle: "Archivos y modelos que las apps de Pinokio guardaron como caché.",
              consecuencia: "Las apps vuelven a descargar lo que necesiten (pueden ser varios GB).")
            .en(.desarrollo).revisar().app("Pinokio", "computer.pinokio"),
        Regla("pinokio-temporales-tmp", "~/pinokio/cache/*TMP*",
              nombre: "Temporales de Pinokio",
              detalle: "Archivos temporales de las apps de Pinokio (TMPDIR, TMP, PIP_TMPDIR).",
              consecuencia: "Nada: Pinokio crea otros cuando los necesita.")
            .en(.temporales).edad(dias: 3).sinArchivosAbiertos().app("Pinokio", "computer.pinokio"),
        Regla("pinokio-temporales-temp", "~/pinokio/cache/TEMP",
              nombre: "Temporales de Pinokio (TEMP)",
              detalle: "Archivos temporales de las apps de Pinokio.",
              consecuencia: "Nada: se vuelven a crear cuando hacen falta.")
            .en(.temporales).edad(dias: 3).sinArchivosAbiertos().app("Pinokio", "computer.pinokio"),
        Regla("pinokio-gradio-temp", "~/pinokio/cache/GRADIO_TEMP_DIR",
              nombre: "Archivos de las apps de Pinokio (Gradio)",
              detalle: "Imágenes, audio y vídeos que subiste o que generaron las apps de Pinokio hechas con Gradio.",
              consecuencia: "Si generaste algo y no lo descargaste, puede que solo esté aquí: revísalo antes de borrar.")
            .en(.temporales).revisar().edad(dias: 7).sinArchivosAbiertos().app("Pinokio", "computer.pinokio"),
        Regla("pinokio-modelos-hf", "~/pinokio/cache/HF_HOME/hub",
              nombre: "Modelos de IA de Pinokio (Hugging Face)",
              detalle: "Modelos de Hugging Face compartidos por todas las apps de Pinokio.",
              consecuencia: "Cada app los vuelve a descargar la próxima vez que la abras (pueden ser decenas de GB).")
            .en(.desarrollo).revisar().app("Pinokio", "computer.pinokio"),
        Regla("pinokio-modelos-torch", "~/pinokio/cache/TORCH_HOME",
              nombre: "Modelos de PyTorch de Pinokio",
              detalle: "Pesos de modelos que PyTorch descargó para las apps de Pinokio.",
              consecuencia: "Se vuelven a descargar la próxima vez que una app los necesite.")
            .en(.desarrollo).revisar().app("Pinokio", "computer.pinokio"),
        Regla("keras-modelos", "~/.keras/models",
              nombre: "Modelos preentrenados de Keras",
              detalle: "Pesos de modelos (ResNet, MobileNet…) que Keras/TensorFlow descargó.",
              consecuencia: "Se vuelven a descargar si un programa los usa.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("tfds-extraidos", "~/tensorflow_datasets/downloads/extracted",
              nombre: "Archivos descomprimidos de TensorFlow Datasets",
              detalle: "Copias descomprimidas de conjuntos de datos que ya se prepararon.",
              consecuencia: "Nada para los conjuntos ya preparados; si preparas uno de nuevo, se vuelve a descomprimir.")
            .en(.desarrollo).proceso("Python", patron: "python"),
        Regla("kagglehub-cache", "~/.cache/kagglehub",
              nombre: "Descargas de Kaggle",
              detalle: "Conjuntos de datos y modelos que descargaste de Kaggle con kagglehub (también los de KerasHub).",
              consecuencia: "Se vuelven a descargar la próxima vez que un programa los pida.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("nltk-datos", "~/nltk_data",
              nombre: "Datos de NLTK",
              detalle: "Diccionarios y textos de ejemplo que descargó NLTK.",
              consecuencia: "Lo que descargó NLTK se vuelve a bajar con nltk.download(). Si guardaste aquí corpus o datos propios, se perderán: revísalo antes.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("gensim-datos", "~/gensim-data",
              nombre: "Datos de Gensim",
              detalle: "Vectores de palabras y textos que descargó Gensim (pueden ocupar varios GB).",
              consecuencia: "Se vuelven a descargar con gensim.downloader si un programa los pide.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("stanza-recursos-antiguos", "~/stanza_resources",
              nombre: "Modelos de Stanza (ubicación antigua)",
              detalle: "Modelos de lenguaje que descargaron versiones antiguas de Stanza.",
              consecuencia: "Las versiones actuales de Stanza ya no usan esta carpeta; si alguna vieja los pide, los vuelve a descargar.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("flair-cache", "~/.flair",
              nombre: "Modelos de Flair",
              detalle: "Modelos, embeddings y conjuntos de datos que descargó Flair.",
              consecuencia: "Se vuelven a descargar la próxima vez que un programa los use.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("openml-cache", "~/.openml/org",
              nombre: "Caché de OpenML",
              detalle: "Conjuntos de datos y tareas que descargó OpenML.",
              consecuencia: "Se vuelven a descargar si un programa los pide. Tu configuración y tu clave de OpenML no se tocan.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("fastai-archivos", "~/.fastai/archive",
              nombre: "Archivos comprimidos de fastai",
              detalle: "Los .tgz de conjuntos de datos que fastai ya descomprimió.",
              consecuencia: "Nada: fastai usa los datos ya descomprimidos y no vuelve a mirar estos archivos.")
            .en(.desarrollo).proceso("Python", patron: "python"),
        Regla("fastai-datos", "~/.fastai/data",
              nombre: "Conjuntos de datos de fastai",
              detalle: "Datos de ejemplo descomprimidos por fastai (cursos, tutoriales).",
              consecuencia: "Se vuelven a descargar si un programa los pide. Ojo: si guardaste modelos entrenados con learn.save() sin cambiar la ruta, están aquí dentro.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("fastdownload-archivos", "~/.fastdownload/archive",
              nombre: "Archivos comprimidos de fastdownload",
              detalle: "Descargas comprimidas que fastdownload ya descomprimió.",
              consecuencia: "Nada: los datos descomprimidos siguen ahí.")
            .en(.desarrollo).proceso("Python", patron: "python"),
        Regla("clip-modelos", "~/.cache/clip",
              nombre: "Modelos CLIP de OpenAI",
              detalle: "Modelos de visión que descargó la librería CLIP.",
              consecuencia: "Se vuelven a descargar la próxima vez que un programa los pida.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("easyocr-modelos", "~/.EasyOCR/model",
              nombre: "Modelos de EasyOCR",
              detalle: "Modelos de reconocimiento de texto que descargó EasyOCR.",
              consecuencia: "Se vuelven a descargar la próxima vez que uses EasyOCR.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("deepface-pesos", "~/.deepface/weights",
              nombre: "Modelos de DeepFace",
              detalle: "Modelos de reconocimiento facial que descargó DeepFace.",
              consecuencia: "Se vuelven a descargar la próxima vez que uses DeepFace.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("insightface-modelos", "~/.insightface/models",
              nombre: "Modelos de InsightFace",
              detalle: "Modelos de análisis facial que descargó InsightFace (los usan muchas apps de intercambio de caras).",
              consecuencia: "Los modelos oficiales se vuelven a descargar. Algunos, como inswapper_128.onnx, ya no se pueden descargar oficialmente: si los pusiste tú, guárdalos antes.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("rembg-modelos-antiguos", "~/.u2net",
              nombre: "Modelos de rembg (ubicación antigua)",
              detalle: "Modelos para quitar fondos de imágenes que descargó rembg.",
              consecuencia: "rembg los vuelve a descargar (en ~/.rembg) la próxima vez que quites un fondo.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("rembg-modelos", "~/.rembg",
              nombre: "Modelos de rembg",
              detalle: "Modelos para quitar fondos de imágenes que descargó rembg.",
              consecuencia: "Se vuelven a descargar la próxima vez que quites un fondo.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("paddlex-modelos", "~/.paddlex/official_models",
              nombre: "Modelos de PaddleOCR / PaddleX",
              detalle: "Modelos de OCR y visión que descargó PaddleX (PaddleOCR 3).",
              consecuencia: "Se vuelven a descargar la próxima vez que se usen.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("paddlex-temporales", "~/.paddlex/temp",
              nombre: "Temporales de PaddleX",
              detalle: "Archivos temporales de PaddleX.",
              consecuencia: "Nada: se crean otros cuando hacen falta.")
            .en(.temporales).edad(dias: 3).sinArchivosAbiertos().proceso("Python", patron: "python"),
        Regla("paddleocr-modelos-antiguos", "~/.paddleocr",
              nombre: "Modelos de PaddleOCR 2",
              detalle: "Modelos de reconocimiento de texto que descargó PaddleOCR 2.",
              consecuencia: "Se vuelven a descargar la próxima vez que uses PaddleOCR.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("chroma-onnx", "~/.cache/chroma/onnx_models",
              nombre: "Modelo de embeddings de Chroma",
              detalle: "El modelo que Chroma descarga para convertir textos en vectores.",
              consecuencia: "Chroma lo vuelve a descargar la próxima vez. Tus bases de vectores no se tocan.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("bark-modelos", "~/.cache/suno",
              nombre: "Modelos de voz Bark",
              detalle: "Modelos de síntesis de voz que descargó Bark (varios GB).",
              consecuencia: "Se vuelven a descargar la próxima vez que generes voz con Bark.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("coqui-tts-modelos", "~/Library/Application Support/tts/*_models--*",
              nombre: "Modelos de voz de Coqui TTS",
              detalle: "Modelos de texto a voz (XTTS y otros) que descargó Coqui TTS.",
              consecuencia: "Se vuelven a descargar la próxima vez que uses esa voz.")
            .en(.desarrollo).revisar().proceso("Python", patron: "python"),
        Regla("docker-modelos-ia", "~/.docker/models",
              nombre: "Modelos de IA de Docker",
              detalle: "Modelos que descargaste con Docker Model Runner (docker model pull).",
              consecuencia: "Tendrás que volver a descargarlos con «docker model pull». Tus imágenes y contenedores no se tocan.")
            .en(.desarrollo).revisar().app("Docker", "com.docker.docker"),
        Regla("continue-indice", "~/.continue/index/lancedb",
              nombre: "Índice de código de Continue",
              detalle: "Índice de búsqueda por significado que el asistente Continue crea de tus proyectos.",
              consecuencia: "Continue vuelve a indexar tus proyectos la próxima vez que abras el editor (tarda un rato).")
            .sinPreseleccion().sinArchivosAbiertos().proceso("Editor con Continue", patron: "helper (plugin)"),
        Regla("anythingllm-modelos", "~/Library/Application Support/anythingllm-desktop/storage/models",
              nombre: "Modelos de AnythingLLM",
              detalle: "Modelos de embeddings, de voz y de chat que AnythingLLM descargó.",
              consecuencia: "AnythingLLM los vuelve a descargar cuando los necesite. Tus documentos y espacios de trabajo no se tocan.")
            .en(.desarrollo).revisar().soloSiEstaInstalada().app("AnythingLLM"),
        Regla("wandb-cache-antigua", "~/.cache/wandb",
              nombre: "Caché de Weights & Biases (ubicación antigua)",
              detalle: "Artefactos que guardaron versiones anteriores de W&B.",
              consecuencia: "Las versiones actuales de W&B usan otra carpeta; si hace falta, se vuelven a descargar.")
            .en(.desarrollo).revisar().proceso("W&B", patron: "wandb"),
        Regla("wandb-staging", "~/Library/Application Support/wandb/artifacts/staging",
              nombre: "Subidas pendientes de Weights & Biases",
              detalle: "Copias de archivos que W&B preparó para subir y que quedaron tras un fallo.",
              consecuencia: "Si alguna subida sigue pendiente, se perderá: comprueba antes en W&B que tus artefactos están subidos.")
            .en(.temporales).revisar().edad(dias: 7).proceso("W&B", patron: "wandb"),
        Regla("jupyter-runtime", "~/Library/Jupyter/runtime",
              nombre: "Archivos de sesiones viejas de Jupyter",
              detalle: "Archivos de conexión de servidores y kernels de Jupyter que ya terminaron.",
              consecuencia: "Nada: Jupyter crea uno nuevo en cada sesión.")
            .en(.temporales).archivos("json", "html").edad(dias: 7).sinArchivosAbiertos().proceso("Jupyter", patron: "jupyter"),
        Regla("jupyterlab-staging", "~/*/share/jupyter/lab/staging",
              nombre: "Compilación temporal de JupyterLab",
              detalle: "Carpeta de trabajo (con node_modules) que JupyterLab usa al compilar extensiones.",
              consecuencia: "Nada: JupyterLab la vuelve a crear si recompilas. Es lo mismo que «jupyter lab clean».")
            .en(.desarrollo).proceso("Jupyter", patron: "jupyter"),
        Regla("jupyterlab-staging-entornos", "~/*/envs/*/share/jupyter/lab/staging",
              nombre: "Compilación temporal de JupyterLab (entornos conda)",
              detalle: "Carpeta de trabajo que JupyterLab dejó al compilar extensiones dentro de un entorno de conda.",
              consecuencia: "Nada: se vuelve a crear si recompilas. Es lo mismo que «jupyter lab clean».")
            .en(.desarrollo).proceso("Jupyter", patron: "jupyter"),
        Regla("jupyterlab-staging-homebrew", "/opt/homebrew/Cellar/jupyterlab/*/libexec/share/jupyter/lab/staging",
              nombre: "Compilación temporal de JupyterLab (Homebrew)",
              detalle: "Carpeta de trabajo de JupyterLab instalado con Homebrew.",
              consecuencia: "Nada: JupyterLab la vuelve a crear si recompilas. Es lo mismo que «jupyter lab clean».")
            .admin().sinPreseleccion().proceso("Jupyter", patron: "jupyter"),
        Regla("jupyterlab-staging-usuario", "~/Library/Python/*/share/jupyter/lab/staging",
              nombre: "Compilación temporal de JupyterLab (pip --user)",
              detalle: "Carpeta de trabajo de JupyterLab instalado con «pip install --user».",
              consecuencia: "Nada: JupyterLab la vuelve a crear si recompilas. Es lo mismo que «jupyter lab clean».")
            .en(.desarrollo).proceso("Jupyter", patron: "jupyter"),
        Regla("jupyterlab-desktop-entorno", "~/Library/jupyterlab-desktop/jlab_server",
              nombre: "Entorno de Python de JupyterLab Desktop",
              detalle: "El Python con JupyterLab que instala la app JupyterLab Desktop (más de 1 GB).",
              consecuencia: "Si sigues usando JupyterLab Desktop, te pedirá instalarlo de nuevo y perderás los paquetes que añadiste a ese entorno (tus cuadernos no se tocan). Si ya borraste la app, es un resto que sobra.")
            .en(.desarrollo).revisar().app("JupyterLab", "org.jupyter.jupyterlab-desktop"),
        Regla("spyder-registros-lsp", "~/.spyder-py3/lsp_logs",
              nombre: "Registros de Spyder",
              detalle: "Registros del servidor de autocompletado de Spyder.",
              consecuencia: "Nada: solo son registros. Tu configuración y tus archivos no se tocan.")
            .en(.registros).app("Spyder", "org.spyder-ide.Spyder-6", "org.spyder-ide.Spyder"),
        Regla("rstudio-registros", "~/.local/share/rstudio/log",
              nombre: "Registros de RStudio",
              detalle: "Registros de RStudio.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).app("RStudio", "com.rstudio.desktop"),
        Regla("r-bibliotecas-viejas", "~/Library/R/arm64/*",
              nombre: "Paquetes de versiones viejas de R",
              detalle: "Paquetes que instalaste para versiones anteriores de R (se conserva la más nueva).",
              consecuencia: "Si vuelves a una versión vieja de R, tendrás que reinstalar sus paquetes. La versión actual no los usa.")
            .en(.desarrollo).revisar().conservando(.versionMasAlta).app("R", "org.R-project.R"),
        Regla("r-bibliotecas-viejas-intel", "~/Library/R/x86_64/*",
              nombre: "Paquetes de versiones viejas de R (Intel)",
              detalle: "Paquetes de versiones anteriores de R para Intel (se conserva la más nueva).",
              consecuencia: "Si vuelves a una versión vieja de R para Intel, tendrás que reinstalar sus paquetes.")
            .en(.desarrollo).revisar().conservando(.versionMasAlta).app("R", "org.R-project.R"),
        Regla("anaconda-navigator-registros", "~/.anaconda/navigator/logs",
              nombre: "Registros de Anaconda Navigator",
              detalle: "Registros de Anaconda Navigator.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("Anaconda Navigator", patron: "anaconda-navigator"),
        Regla("anaconda-navigator-contenido", "~/.anaconda/navigator/content",
              nombre: "Contenido descargado por Anaconda Navigator",
              detalle: "Noticias, vídeos y tutoriales que Navigator descarga para su pantalla de inicio.",
              consecuencia: "Navigator lo vuelve a descargar al abrirse.")
            .proceso("Anaconda Navigator", patron: "anaconda-navigator"),
        Regla("anaconda-navigator-imagenes", "~/.anaconda/navigator/images",
              nombre: "Imágenes de Anaconda Navigator",
              detalle: "Iconos e imágenes que Navigator descargó.",
              consecuencia: "Navigator las vuelve a descargar.")
            .proceso("Anaconda Navigator", patron: "anaconda-navigator"),
        Regla("anaconda-navigator-caches", "~/.anaconda/navigator/*_cache",
              nombre: "Cachés de Anaconda Navigator",
              detalle: "Anuncios y datos de la nube que Navigator guarda para no descargarlos otra vez.",
              consecuencia: "Navigator los vuelve a descargar.")
            .proceso("Anaconda Navigator", patron: "anaconda-navigator"),
        Regla("streamlit-cache", "~/.streamlit/cache",
              nombre: "Caché de Streamlit",
              detalle: "Resultados que tus apps de Streamlit guardaron en disco para no recalcularlos.",
              consecuencia: "Tus apps de Streamlit recalcularán esos resultados la próxima vez. Tu configuración y tus credenciales no se tocan.")
            .en(.desarrollo).proceso("Streamlit", patron: "streamlit"),
        Regla("dvc-cache-del-sitio", "/Library/Caches/dvc",
              nombre: "Índices de DVC",
              detalle: "Índices y estado que DVC guarda de tus repositorios de datos para ir más rápido.",
              consecuencia: "DVC los vuelve a calcular (el próximo «dvc status» irá más lento). Tus datos no se tocan.")
            .admin().sinPreseleccion().proceso("DVC", patron: "dvc"),
        Regla("dvc-cache-del-sitio-homebrew", "/opt/homebrew/var/cache/dvc",
              nombre: "Índices de DVC (Homebrew)",
              detalle: "Índices y estado que DVC guarda de tus repositorios de datos para ir más rápido.",
              consecuencia: "DVC los vuelve a calcular (el próximo «dvc status» irá más lento). Tus datos no se tocan.")
            .admin().sinPreseleccion().proceso("DVC", patron: "dvc"),
        Regla("createml-cache", "~/Library/Containers/com.apple.CreateML/Data/Library/Caches",
              nombre: "Caché de Create ML",
              detalle: "Archivos temporales de la app Create ML de Apple.",
              consecuencia: "Create ML los vuelve a crear. Tus proyectos y modelos entrenados no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Create ML", "com.apple.CreateML"),
        Regla("matplotlib-tex-cache", "~/.matplotlib/tex.cache",
              nombre: "Caché de fórmulas de Matplotlib",
              detalle: "Fórmulas LaTeX que Matplotlib ya dibujó en tus gráficos.",
              consecuencia: "Matplotlib las vuelve a generar la próxima vez que hagas esos gráficos.")
            .en(.desarrollo),
    ]
}
