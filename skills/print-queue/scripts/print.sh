#!/usr/bin/env bash
set -euo pipefail

# Print Queue - Document Printing Script
# Prints documents to Brother printer at 192.168.0.104 via IPP/CUPS

PRINTER_NAME="DCPT520W"
PRINTER_URI="lpd://192.168.0.104/BINARY_P1"
PRINTER_MODEL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") <file> [options]

Print documents to Brother network printer.

Arguments:
  file              Document file to print (PDF, JPG, PNG, TXT)

Options:
  --copies N        Number of copies (default: 1)
  --pages RANGE     Page range: 1, 1-3, 1,3,5 (default: all pages)
  --media SIZE      Paper size: A4, Letter, Legal (default: A4)
  --quality Q       Quality: draft, normal, high
  --duplex ON/OFF   Double-sided printing
  --job-name NAME   Custom job name
  -h, --help        Show this help

Examples:
  $(basename "$0") document.pdf
  $(basename "$0") document.pdf --pages 1
  $(basename "$0") document.pdf --pages 1-3
  $(basename "$0") photo.jpg --copies 2 --quality high
  $(basename "$0") contract.pdf --duplex ON --media A4

Printer: $PRINTER_NAME ($PRINTER_URI)
EOF
    exit 2
}

log_info() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}" >&2; }

# Check prerequisites
check_prerequisites() {
    local missing=0

    if ! command -v lp &> /dev/null; then
        log_error "CUPS lp command not found. Install with: sudo apt install cups-client"
        missing=1
    fi

    if ! command -v file &> /dev/null; then
        log_error "file command not found. Install with: sudo apt install file"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

# Check if printer is configured
check_printer() {
    if ! lpstat -p "$PRINTER_NAME" &> /dev/null; then
        log_warn "Printer '$PRINTER_NAME' not found. Attempting to add..."
        
        if command -v lpadmin &> /dev/null; then
            sudo lpadmin -p "$PRINTER_NAME" -v "$PRINTER_URI" -E -m raw 2>/dev/null || {
                log_error "Failed to add printer. Run manually:"
                echo "  sudo lpadmin -p $PRINTER_NAME -v $PRINTER_URI -E"
                exit 1
            }
            log_info "Printer '$PRINTER_NAME' added successfully"
        else
            log_error "CUPS not installed. Install with: sudo apt install cups"
            exit 1
        fi
    fi
    
    log_info "Printer '$PRINTER_NAME' is ready"
}

# Validate file
validate_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        exit 1
    fi
    
    if [[ ! -s "$file" ]]; then
        log_error "File is empty: $file"
        exit 1
    fi
    
    # Check file type
    local mime_type
    mime_type=$(file --mime-type -b "$file" 2>/dev/null || echo "application/octet-stream")
    
    case "$mime_type" in
        application/pdf)
            echo "pdf"
            ;;
        image/jpeg|image/png|image/tiff)
            echo "image"
            ;;
        text/plain)
            echo "text"
            ;;
        *)
            log_warn "Unsupported file type: $mime_type"
            log_info "Supported types: PDF, JPG, PNG, TIFF, TXT"
            exit 1
            ;;
    esac
}

# Parse arguments
copies=1
pages=""
media="A4"
quality=""
duplex=""
job_name=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --copies)
            copies="${2:-1}"; shift 2 ;;
        --pages)
            pages="${2:-}"; shift 2 ;;
        --media)
            media="${2:-A4}"; shift 2 ;;
        --quality)
            quality="${2:-}"; shift 2 ;;
        --duplex)
            duplex="${2:-}"; shift 2 ;;
        --job-name)
            job_name="${2:-}"; shift 2 ;;
        -h|--help)
            usage ;;
        -*)
            log_error "Unknown option: $1"
            usage ;;
        *)
            if [[ -z "${file:-}" ]]; then
                file="$1"
            else
                log_error "Multiple files specified: $file and $1"
                exit 1
            fi
            shift ;;
    esac
done

# Check file argument
if [[ -z "${file:-}" ]]; then
    log_error "No file specified"
    usage
fi

# Validate file and get type
file_type=$(validate_file "$file")

# Main execution
main() {
    echo "🖨️ Print Queue - Document Printing"
    echo "=================================="
    
    check_prerequisites
    check_printer
    
    echo ""
    echo "📄 File: $file"
    echo "📋 Type: $file_type"
    echo "⚙️  Options: copies=$copies, pages=$pages, media=$media"
    echo ""
    
    # Build lp options
    lp_options="-d $PRINTER_NAME -n $copies -o media=$media"
    
    if [[ -n "$pages" ]]; then
        lp_options="$lp_options -o page-ranges=$pages"
    fi
    
    if [[ -n "$quality" ]]; then
        lp_options="$lp_options -o print-quality=$quality"
    fi
    
    if [[ -n "$duplex" ]]; then
        lp_options="$lp_options -o sides=two-sided-long-edge"
    fi
    
    if [[ -n "$job_name" ]]; then
        lp_options="$lp_options -t \"$job_name\""
    fi
    
    echo "⚙️  Options: copies=$copies, media=$media"
    echo ""
    
    # Submit print job
    log_info "Submitting print job..."
    
    if eval "lp $lp_options \"$file\""; then
        echo ""
        log_info "Print job submitted successfully!"
        echo ""
        echo "📋 Job Status:"
        lpstat -p "$PRINTER_NAME" -W not-completed
        
        echo ""
        echo "✅ Done! The document will be printed to $PRINTER_NAME"
    else
        log_error "Failed to submit print job"
        exit 1
    fi
}

main "$@"
