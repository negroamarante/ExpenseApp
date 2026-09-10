import { createElement } from "lwc";
import BudgetDashboard from "c/budgetDashboard";
import getMonthSummary from "@salesforce/apex/BudgetController.getMonthSummary";
import { refreshApex } from "@salesforce/apex";
import { deleteRecord } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";
import ExpenseFormModal from "c/expenseFormModal";
import BudgetEditModal from "c/budgetEditModal";

jest.mock(
  "@salesforce/apex/BudgetController.getMonthSummary",
  () => {
    const {
      createApexTestWireAdapter
    } = require("@salesforce/wire-service-jest-util");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn().mockResolvedValue() }),
  { virtual: true }
);

jest.mock("c/expenseFormModal", () => ({
  __esModule: true,
  default: { open: jest.fn().mockResolvedValue("cancel") }
}));

jest.mock("c/budgetEditModal", () => ({
  __esModule: true,
  default: { open: jest.fn().mockResolvedValue("cancel") }
}));

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_SUMMARY = {
  monthStart: "2026-09-01",
  monthLabel: "septiembre 2026",
  budgetAmount: 1000,
  committedAmount: 400,
  availableAmount: 600,
  percentUsed: 40,
  hasBudget: true,
  expenses: [
    {
      id: "a01000000000001",
      description: "Supermercado",
      installmentAmount: 400,
      numberOfInstallments: 1,
      installmentNumber: 1,
      category: "Comida",
      person: "Diego"
    }
  ]
};

describe("c-budget-dashboard", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the budget tiles once the summary wire emits data", async () => {
    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);

    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const tileValues = element.shadowRoot.querySelectorAll(".tile-value");
    expect(
      tileValues[0].querySelector("lightning-formatted-number").value
    ).toBe(1000);
    expect(
      element.shadowRoot.querySelector(
        ".available-value lightning-formatted-number"
      ).value
    ).toBe(600);
    expect(element.shadowRoot.querySelector(".month-label").textContent).toBe(
      "SEPTIEMBRE 2026"
    );
  });

  it("moves the wire config to the next month when the arrow is clicked", async () => {
    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const initialMonthStart = getMonthSummary.getLastConfig().monthStart;

    element.shadowRoot
      .querySelectorAll(".month-nav lightning-button-icon")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    const nextMonthStart = getMonthSummary.getLastConfig().monthStart;
    expect(nextMonthStart).not.toBe(initialMonthStart);
    expect(nextMonthStart.endsWith("-10-01")).toBe(true);
  });

  it("refreshes the summary after adding an expense successfully", async () => {
    ExpenseFormModal.open.mockResolvedValue("success");

    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot.querySelector(".fab").click();
    await flushPromises();

    expect(ExpenseFormModal.open).toHaveBeenCalled();
    expect(refreshApex).toHaveBeenCalledWith(expect.anything());
  });

  it("deletes an expense after confirmation", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    deleteRecord.mockResolvedValue();

    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot.querySelector("c-expense-list").dispatchEvent(
      new CustomEvent("delete", {
        detail: { expenseId: "a01000000000001" }
      })
    );
    await flushPromises();

    expect(deleteRecord).toHaveBeenCalledWith("a01000000000001");
    expect(refreshApex).toHaveBeenCalled();
  });

  it("does not delete when the confirmation is dismissed", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(false);

    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot.querySelector("c-expense-list").dispatchEvent(
      new CustomEvent("delete", {
        detail: { expenseId: "a01000000000001" }
      })
    );
    await flushPromises();

    expect(deleteRecord).not.toHaveBeenCalled();
  });

  it("shows a friendly message when deletion is blocked by permissions", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    deleteRecord.mockRejectedValue({
      body: { errorCode: "INSUFFICIENT_ACCESS_OR_READONLY" }
    });

    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    element.shadowRoot.querySelector("c-expense-list").dispatchEvent(
      new CustomEvent("delete", {
        detail: { expenseId: "a01000000000001" }
      })
    );
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "No tenés permiso para eliminar este consumo."
    );
  });

  it("opens the budget edit modal with the current amount and refreshes on success", async () => {
    BudgetEditModal.open.mockResolvedValue("success");

    const element = createElement("c-budget-dashboard", {
      is: BudgetDashboard
    });
    document.body.appendChild(element);
    getMonthSummary.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot
      .querySelector(".tile-label-row lightning-button-icon")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(BudgetEditModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ currentAmount: 1000 })
    );
    expect(refreshApex).toHaveBeenCalled();
  });
});
