export class TableSortFilter {
  constructor(table) {
    this.table = table
    const headerRow = this.table.querySelector('thead tr')
    this.headers = Array.from(headerRow.children)
    this.cols = this.headers.filter(th => th.textContent !== '').length
    this.col = 0
    this.asc = true

    this.hookSorting()
    this.filterInput = this.hookFilter()
  }

  hookFilter() {
    const filterInput = this.table.previousElementSibling
    if (filterInput === null || filterInput.nodeName.toUpperCase() !== 'INPUT')
      return null

    let timer = null
    filterInput.addEventListener('keyup', evt => {
      if (timer !== null)
        clearTimeout(timer)
      timer = setTimeout(() => {
        timer = null;
        this.filter()
      }, 500)
    })

    return filterInput
  }

  hookSorting() {
    for (let th of this.headers) {
      th.addEventListener('click', evt => this.onSortingClick(evt))
    }
  }

  onSortingClick(evt) {
    const th = evt.target
    this.headers[this.col].classList.remove(this.asc?'sorted-asc':'sorted-desc')
    const col = this.headers.indexOf(th)
    if (this.col === col)
      this.asc = !this.asc
    else {
      this.col = col
      this.asc = true
    }

    this.sort()
  }

  // filter

  filter() {
    const text = this.filterInput === null ? undefined : this.filterInput.value
    if (text === undefined)
      return

    const cols = this.cols
    if (text === '') {
      for (let tr of this.table.querySelectorAll('tbody tr'))
        tr.classList.remove('hidden')
    } else {
      const cmpStr = text.toLowerCase()
      console.log("Filter:", cmpStr)
      for (let tr of this.table.querySelectorAll('tbody tr')) {
        let show = false
        for (let i = 0; i < cols; i++) {
          if (tr.children.item(i).textContent.toLowerCase().indexOf(cmpStr) >= 0) {
            show = true
            break
          }
        }
        if (show)
          tr.classList.remove('hidden')
        else
          tr.classList.add('hidden')
      }
    }
  }

  // sort

  comparer(col, asc) {
    const value = tr => {
      const td = tr.children[col]
      if (td !== undefined)
        //return td.innerText || td.textContent
        return td.textContent
      return ''
    }
    const cmp = (a, b) => {
      if (a !== '' && b !== '' && !isNaN(a) && !isNaN(b))
        return a - b
      return a.toString().localeCompare(b)
    }
    return (tr1, tr2) => {
      const v1 = value(tr1)
      const v2 = value(tr2)
      if (v1 === undefined || v2 === undefined)
        return undefined
      return asc ? cmp(v1, v2) : cmp(v2, v1)
    }
  }

  sort() {
    if (this.col < 0)
      return

    const tbody = this.table.querySelector('tbody')
    Array.from(tbody.children)
      .sort(this.comparer(this.col, this.asc))
      .forEach(tr => tbody.appendChild(tr))

    this.headers[this.col].classList.add(this.asc?'sorted-asc':'sorted-desc')
  }
}

export const PhoenixTableSortFilterHook = {
  mounted() {
    console.log("PhoenixTableSortFilterHook:mounted")
    if (this.el.nodeName.toUpperCase() == 'TABLE') {
      this.tsf = new TableSortFilter(this.el)
    }
  },

  updated() {
    console.log("PhoenixTableSortFilterHook:updated")
    this.tsf.sort()
    this.tsf.filter()
  },
}


// vim: set ts=2 sw=2 tw=2 et syn=javascript ft=javascript :
