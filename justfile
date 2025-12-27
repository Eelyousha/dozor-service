# Justfile для генерации UML-диаграмм с помощью PlantUML

# Формат вывода по умолчанию (png, svg, eps, pdf)
format := "png"

# Директория для выходных файлов
output_dir := "uml-output"

# Показать все доступные рецепты
default:
    @just --list

# Сгенерировать UML-диаграммы для всех .puml файлов
all: setup
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    for file in *.puml *.plantuml; do
        [[ -f "$file" ]] || continue
        echo "Генерация диаграммы для: $file"
        plantuml -t{{format}} -o "{{output_dir}}" "$file"
    done
    echo "✓ Все диаграммы сохранены в {{output_dir}}/"

# Сгенерировать диаграмму для конкретного файла
generate file:
    @mkdir -p {{output_dir}}
    plantuml -t{{format}} -o "{{output_dir}}" {{file}}
    @echo "✓ Диаграмма сохранена в {{output_dir}}/"

# Сгенерировать диаграммы в формате SVG
svg: (all-with-format "svg")

# Сгенерировать диаграммы в формате PNG
png: (all-with-format "png")

# Сгенерировать диаграммы в формате PDF
pdf: (all-with-format "pdf")

# Вспомогательный рецепт для генерации в указанном формате
all-with-format fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{output_dir}}
    shopt -s nullglob
    for file in *.puml *.plantuml; do
        [[ -f "$file" ]] || continue
        echo "Генерация диаграммы ({{fmt}}): $file"
        plantuml -t{{fmt}} -o "{{output_dir}}" "$file"
    done
    echo "✓ Все диаграммы сохранены в {{output_dir}}/"

# Следить за изменениями и автоматически перегенерировать
watch:
    #!/usr/bin/env bash
    echo "Наблюдение за .puml/.plantuml файлами... (Ctrl+C для остановки)"
    while true; do
        inotifywait -q -e modify,create *.puml *.plantuml 2>/dev/null && \
        just all
    done

# Создать директорию для вывода
setup:
    @mkdir -p {{output_dir}}

# Очистить сгенерированные файлы
clean:
    rm -rf {{output_dir}}
    @echo "✓ Директория {{output_dir}} удалена"

# Проверить синтаксис всех .puml файлов (современный способ)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0
    shopt -s nullglob
    for file in *.puml *.plantuml; do
        [[ -f "$file" ]] || continue
        echo -n "Проверка: $file ... "
        if plantuml --check-syntax "$file" > /dev/null 2>&1; then
            echo "✓ OK"
        else
            echo "✗ ОШИБКА"
            plantuml --check-syntax "$file"
            ((errors++)) || true
        fi
    done
    if [[ $errors -eq 0 ]]; then
        echo "✓ Все файлы корректны"
    else
        echo "✗ Найдено ошибок: $errors"
        exit 1
    fi

# Проверить синтаксис конкретного файла
lint-file file:
    @plantuml --check-syntax {{file}}

# Быстрая проверка синтаксиса всех файлов перед генерацией
check-before-run:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Быстрая проверка синтаксиса всех файлов..."
    shopt -s nullglob
    for file in *.puml *.plantuml; do
        [[ -f "$file" ]] || continue
        plantuml --check-syntax "$file" > /dev/null 2>&1 || {
            echo "✗ Ошибка синтаксиса в: $file"
            plantuml --check-syntax "$file"
            exit 1
        }
    done
    echo "✓ Все файлы прошли проверку синтаксиса"

# Проверить установку PlantUML
check:
    @which plantuml > /dev/null 2>&1 && echo "✓ PlantUML установлен" || echo "✗ PlantUML не найден. Установите: sudo apt install plantuml"
    @which java > /dev/null 2>&1 && echo "✓ Java установлена" || echo "✗ Java не найдена"

# Создать пример .puml файла
example:
    #!/usr/bin/env bash
    cat > example.puml << 'EOF'
    @startuml
    title Пример диаграммы классов

    class User {
        +id: int
        +name: string
        +email: string
        +register()
        +login()
    }

    class Order {
        +id: int
        +total: float
        +status: string
        +create()
        +cancel()
    }

    User "1" -- "*" Order : создаёт

    @enduml
    EOF
    echo "✓ Создан example.puml"
