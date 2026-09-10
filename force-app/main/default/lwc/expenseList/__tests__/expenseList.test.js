import { createElement } from "lwc";
import ExpenseList from "c/expenseList";

const SAMPLE_EXPENSES = [
  {
    id: "a01000000000001",
    description: "Supermercado",
    category: "Comida",
    person: "Diego",
    installmentAmount: 1000,
    numberOfInstallments: 1,
    installmentNumber: 1
  },
  {
    id: "a01000000000002",
    description: "Notebook",
    category: null,
    person: "Emi",
    installmentAmount: 500,
    numberOfInstallments: 3,
    installmentNumber: 2
  }
];

describe("c-expense-list", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the empty state when there are no expenses", () => {
    const element = createElement("c-expense-list", { is: ExpenseList });
    element.expenses = [];
    document.body.appendChild(element);

    const empty = element.shadowRoot.querySelector(".empty-state");
    expect(empty).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll(".expense-item").length).toBe(0);
  });

  it("renders one item per expense with the right labels", () => {
    const element = createElement("c-expense-list", { is: ExpenseList });
    element.expenses = SAMPLE_EXPENSES;
    document.body.appendChild(element);

    const items = element.shadowRoot.querySelectorAll(".expense-item");
    expect(items.length).toBe(2);

    const metas = element.shadowRoot.querySelectorAll(".expense-meta");
    expect(metas[0].textContent).toContain("Comida");
    expect(metas[0].textContent).toContain("Pago único");
    expect(metas[1].textContent).toContain("Sin categoría");
    expect(metas[1].textContent).toContain("Cuota 2/3");
  });

  it("dispatches an edit event with the expense id when the row is clicked", () => {
    const element = createElement("c-expense-list", { is: ExpenseList });
    element.expenses = SAMPLE_EXPENSES;
    document.body.appendChild(element);

    const editHandler = jest.fn();
    element.addEventListener("edit", editHandler);

    return Promise.resolve().then(() => {
      element.shadowRoot.querySelector(".expense-main").click();
      expect(editHandler).toHaveBeenCalledTimes(1);
      expect(editHandler.mock.calls[0][0].detail.expenseId).toBe(
        SAMPLE_EXPENSES[0].id
      );
    });
  });

  it("dispatches a delete event without triggering edit", () => {
    const element = createElement("c-expense-list", { is: ExpenseList });
    element.expenses = SAMPLE_EXPENSES;
    document.body.appendChild(element);

    const editHandler = jest.fn();
    const deleteHandler = jest.fn();
    element.addEventListener("edit", editHandler);
    element.addEventListener("delete", deleteHandler);

    return Promise.resolve().then(() => {
      element.shadowRoot
        .querySelector("lightning-button-icon")
        .dispatchEvent(new CustomEvent("click", { bubbles: true }));

      expect(deleteHandler).toHaveBeenCalledTimes(1);
      expect(deleteHandler.mock.calls[0][0].detail.expenseId).toBe(
        SAMPLE_EXPENSES[0].id
      );
      expect(editHandler).not.toHaveBeenCalled();
    });
  });
});
