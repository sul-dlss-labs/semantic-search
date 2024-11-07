import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    druid: String
  }

  static targets = [ "title", "abstract", "canvas", "date" ]
  connect(e) {
    // e.preventDefault()
    console.log('load metadata for ' + this.druidValue)
    fetch(`https://purl.stanford.edu/${this.druidValue}.json`)
      .then(response => response.json())
      .then(json => this.setJson(json))
  }

  setJson(json) {
    this.titleTarget.innerHTML = json.label
    this.abstractTarget.innerHTML = json.description.note.find((note) => note.type === "abstract")?.value
    const date = json.description.event[0].date[0]
    this.dateTarget.innerHTML = `${date.type} ${date.value}`
    const filename = json.structural.contains[0].structural.contains[0].filename
    const pdf_url = `https://stacks.stanford.edu/file/${json.externalIdentifier}/${filename}`
    this.setPdfImage(pdf_url)
  }

  setPdfImage(url) {
    const canvas = this.canvasTarget;
    canvas.width = this.element.clientWidth;
    console.log(this.element)
    // Load the PDF
    pdfjsLib.getDocument(url).promise.then(pdf => {
      // Get the first page
      pdf.getPage(1).then(page => {
        const scale = canvas.width / page.getViewport({scale: 1}).width; // Set the zoom scale
        console.log(scale)
        const viewport = page.getViewport({ scale });

        const context = canvas.getContext('2d');
        // canvas.height = viewport.height;
        // canvas.width = viewport.width;

        // Render the page
        const renderContext = {
          canvasContext: context,
          viewport: viewport,
        };
        page.render(renderContext);
      });
    });
  }

}
