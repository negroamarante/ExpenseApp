import { createElement } from "lwc";
import SpendingDashboard from "c/spendingDashboard";
import getMonthSpending from "@salesforce/apex/SpendingController.getMonthSpending";
import { refreshApex } from "@salesforce/apex";
import { deleteRecord } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";
import ExpenseFormModal from "c/expenseFormModal";

jest.mock(
  "@salesforce/apex/SpendingController.getMonthSpending",
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

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_SUMMARY = {
  monthStart: "2026-09-01",
  monthLabel: "septiembre 2026",
  totalSpent: 12000,
  expenses: [
    {
      id: "a01000000000001",
      description: "Verdulería",
      totalAmount: 12000,
      installmentAmount: 12000,
      numberOfInstallments: 1,
      installmentNumber: 1,
      category: "Supermercado",
      person: "Diego",
      paymentMethod: "Efectivo",
      countsTowardBudget: false
    }
  ]
};

describe("c-spending-dashboard", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the total spent and expense list once the wire emits data", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);

    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".tile-value lightning-formatted-number")
        .value
    ).toBe(12000);
    expect(element.shadowRoot.querySelector(".month-label").textContent).toBe(
      "SEPTIEMBRE 2026"
    );
    expect(element.shadowRoot.querySelectorAll(".expense-row").length).toBe(1);
  });

  it("shows the empty state when there are no expenses", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);

    getMonthSpending.emit({ ...SAMPLE_SUMMARY, expenses: [] });
    await flushPromises();

    expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();
  });

  it("shows a dual-tracking label when the expense also counts toward the budget", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);

    getMonthSpending.emit({
      ...SAMPLE_SUMMARY,
      expenses: [{ ...SAMPLE_SUMMARY.expenses[0], countsTowardBudget: true }]
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".expense-meta").textContent
    ).toContain("También en límite cupo");
  });

  it("moves to the next month when the arrow is clicked and revalidates via refreshApex", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const initialMonthStart = getMonthSpending.getLastConfig().monthStart;

    element.shadowRoot
      .querySelectorAll(".month-nav lightning-button-icon")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    const nextMonthStart = getMonthSpending.getLastConfig().monthStart;
    expect(nextMonthStart).not.toBe(initialMonthStart);

    getMonthSpending.emit({
      ...SAMPLE_SUMMARY,
      monthStart: nextMonthStart,
      monthLabel: "octubre 2026",
      totalSpent: 500
    });
    await flushPromises();

    expect(refreshApex).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".month-label").textContent).toBe(
      "OCTUBRE 2026"
    );
  });

  it("jumps back to the current month from the header button", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const currentMonthStart = getMonthSpending.getLastConfig().monthStart;

    element.shadowRoot
      .querySelectorAll(".month-nav lightning-button-icon")[1]
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".current-month-button")
    ).not.toBeNull();

    element.shadowRoot
      .querySelector(".current-month-button")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(getMonthSpending.getLastConfig().monthStart).toBe(currentMonthStart);
  });

  it("opens the form modal in spending mode when adding an expense and refreshes on success", async () => {
    ExpenseFormModal.open.mockResolvedValue("success");

    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot.querySelector(".fab").click();
    await flushPromises();

    expect(ExpenseFormModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ mode: "spending" })
    );
    expect(refreshApex).toHaveBeenCalled();
  });

  it("opens the form modal to edit an expense with its id", async () => {
    ExpenseFormModal.open.mockResolvedValue("cancel");

    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot.querySelector(".expense-main").click();
    await flushPromises();

    expect(ExpenseFormModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        mode: "spending",
        expenseId: "a01000000000001"
      })
    );
  });

  it("deletes an expense after confirmation", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    deleteRecord.mockResolvedValue();

    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot
      .querySelector(".expense-side lightning-button-icon")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(deleteRecord).toHaveBeenCalledWith("a01000000000001");
    expect(refreshApex).toHaveBeenCalled();
  });

  it("does not delete when the confirmation is dismissed", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(false);

    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    element.shadowRoot
      .querySelector(".expense-side lightning-button-icon")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(deleteRecord).not.toHaveBeenCalled();
  });

  it("shows an error toast when the wire adapter errors", async () => {
    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    getMonthSpending.error({ message: "Boom" });
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail.message).toBe("Boom");
  });

  it("shows an error toast when deleting fails", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    deleteRecord.mockRejectedValue({ body: { message: "No se pudo borrar" } });

    const element = createElement("c-spending-dashboard", {
      is: SpendingDashboard
    });
    document.body.appendChild(element);
    getMonthSpending.emit(SAMPLE_SUMMARY);
    await flushPromises();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    element.shadowRoot
      .querySelector(".expense-side lightning-button-icon")
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "No se pudo borrar"
    );
  });
});
