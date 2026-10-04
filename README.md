# Retail Customer Churn and Segmentation

Retail customers rarely tell a business when they have stopped shopping. They simply stop placing orders, which makes it difficult to distinguish a lost customer from someone who buys less frequently.

This project uses purchase history to explore that problem. It brings together SQL Server, Python, and Power BI to understand customer behavior, identify customers who may not return, and compare different approaches to customer segmentation.

The analysis uses the Online Retail II dataset from the UCI Machine Learning Repository.

## What the project investigates

- How do purchasing patterns differ between returning and non-returning customers?
- Which customer segments have the highest rates of inactivity?
- How well can purchase history predict whether a customer will return within 90 days?
- Do K-means clusters reveal different patterns from rule-based RFM segments?
- How can these findings help a team prioritize customers for further attention?

## Dataset

[Online Retail II — UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/502/online+retail+ii)

The source contains approximately 1.07 million transaction records from a UK-based online retailer between December 2009 and December 2011.

The main fields include invoice number, product code, quantity, invoice date, unit price, customer ID, and country. Prices are recorded in pounds sterling.

The saved analysis contains **5,285 customers** who made at least one valid purchase before the feature cutoff.

Raw data and generated CSV files are excluded from this repository. They can be recreated by following the workflow below.

## How churn is defined

There is no explicit churn label in this dataset, so the project uses a defined observation window:

> A customer is labeled as churned if they make no valid purchase during the 90 days following the cutoff date.

Customers who purchase during that window receive a label of `0`. Customers who do not receive a label of `1`.

The SQL pipeline reserves the final 90 days of the available data for measuring this outcome. Customer features are calculated using purchases before that window.

This measures **90-day non-return**, rather than proving that a customer has permanently left the business.

## Data preparation

The SQL workflow:

1. Loads both years of transaction data into staging tables.
2. Separates records with invalid numeric or date values for review.
3. Converts valid records to the required data types.
4. Flags cancellation invoices.
5. Keeps positive-quantity, positive-price purchases for analysis.
6. Excludes missing customer IDs when building customer-level features.
7. Creates the RFM features, customer segments, and 90-day outcome label.

The monetary feature is the value of positive purchases before the cutoff. Because cancellation records are excluded rather than reconciled against their original purchases, it should not be interpreted as net revenue after refunds.

## Customer features

The project uses Recency, Frequency, and Monetary value:

| Feature | Definition |
|---|---|
| Recency | Days since the customer's most recent purchase at the cutoff |
| Frequency | Number of distinct purchase invoices before the cutoff |
| Monetary | Total positive purchase value before the cutoff |
| Country | Most frequent country by invoice count in the customer's purchase history |

SQL assigns each RFM measure a score from 1 to 5 and combines these scores into five reporting segments:

- Champions
- New Customers
- At Risk
- Lost
- Needs Attention

These are rule-based labels. For example, “New Customers” describes recent, low-frequency purchasers; it does not independently verify when their relationship with the retailer began.

## Churn modeling

Four classifiers are compared:

- Logistic Regression
- Random Forest
- Gradient Boosting
- Multilayer Perceptron (MLP)

The model inputs are recency, frequency, monetary value, and grouped country. Customer IDs, RFM scores, and segment labels are excluded from the predictors.

The notebook uses a stratified 80/20 customer split:

- **Training:** 4,228 customers
- **Evaluation:** 1,057 customers

Features and outcomes are separated by time, but the model evaluation itself uses a random customer split at a single cutoff. It is not a rolling forecast evaluation.

### Results from the saved notebook run

| Model | ROC-AUC | Recall for non-returning customers |
|---|---:|---:|
| Logistic Regression | 0.813 | 0.705 |
| Random Forest | 0.775 | 0.785 |
| Gradient Boosting | 0.809 | 0.810 |
| MLP | 0.812 | 0.773 |

**Gradient Boosting** was selected because it had the highest recall for non-returning customers at the default classification threshold.

Logistic Regression had the highest ROC-AUC. This distinction matters: the selected model found more non-returning customers at that threshold, while Logistic Regression had slightly stronger overall ranking performance.

The recall-based selection reflects a preference for finding more potentially inactive customers. It does not establish the most cost-effective retention strategy.

These results are exploratory because the same evaluation split was used to compare and select models. A separate validation process and an untouched test period are needed for a stronger performance estimate.

## Model explanations

The classification notebook includes feature-importance plots and SHAP explanations.

In the saved SHAP results, recency has the largest average contribution to the selected model's predictions, followed by monetary value and frequency.

These explanations help describe what the model learned. They do not show that changing a customer's purchasing behavior would cause a particular outcome.

## Customer segmentation

The segmentation notebook compares the SQL RFM groups with K-means clustering.

It:

- Applies a log transformation to frequency and monetary value.
- Standardizes the clustering features.
- Compares cluster counts from 2 to 10 using inertia and silhouette scores.
- Uses three clusters in the final configuration.
- Profiles the clusters and compares them with the SQL segments.

The final choice of three clusters is a manual interpretability decision, rather than an automatic selection of the highest silhouette score.

## Findings from the saved analysis

- **56.7%** of the analyzed customers made no valid purchase during the following 90 days.
- Returning customers had a median recency of **67 days**, compared with **287 days** for non-returning customers.
- Returning customers had a median of **5 previous orders**, compared with **2** for non-returning customers.
- The Champions segment had an observed non-return rate of approximately **19%**, compared with approximately **86%** for the Lost segment.

These findings suggest that recent and repeated purchasing activity is useful for identifying customers who are more likely to return. They also provide a starting point for investigating customer groups with different retention needs.

## Power BI report

The repository includes `Retail_Churn_Dashboard.pbix`.

The Python notebooks generate two files for reporting:

- `data/model_outputs/churn_predictions.csv`
- `data/model_outputs/customer_segments.csv`

Both contain `customer_id`, allowing prediction and segmentation outputs to be connected in Power BI.

The prediction export includes scores for all customers, including those used for training. Dashboard scores should therefore be treated as a demonstration of the workflow, rather than independent evidence of model performance.

## Repository structure

```text
retail-churn-capstone/
├── data/
│   ├── raw/
│   ├── staged/
│   └── model_outputs/                 # Generated by the notebooks
├── notebook/
│   ├── 01_eda.ipynb
│   ├── 02_churn_classification.ipynb
│   └── 03_customer_segmentation.ipynb
├── sql/
│   ├── 01_staging.sql
│   ├── 02_cleaning.sql
│   ├── 03_rfm_features.sql
│   └── 04_export_views.sql
├── Retail_Churn_Dashboard.pbix
└── .gitignore
```

## Running the project

### 1. Prepare the source data

Download the Online Retail II workbook from UCI.

Export its two worksheets as UTF-8 CSV files, keeping the original eight-column order:

```text
data/raw/online_retail_2009_2010.csv
data/raw/online_retail_2010_2011.csv
```

Use an unambiguous date format, such as `YYYY-MM-DD HH:MM:SS`.

### 2. Run the SQL pipeline

Create a SQL Server database named:

```text
RetailChurnCapstone
```

Update the file paths in `sql/01_staging.sql` to match your machine. SQL Server must have permission to read those files.

Run the scripts in this order:

```text
01_staging.sql
02_cleaning.sql
03_rfm_features.sql
04_export_views.sql
```

The scripts recreate their working tables, so use a dedicated project database.

Export `export.customer_rfm_final` as a CSV with column headers and save it as:

```text
data/staged/customer_rfm_final.csv
```

### 3. Run the Python notebooks

Install the packages used by the notebooks:

```bash
pip install pandas numpy matplotlib seaborn scikit-learn shap jupyter
```

Open Jupyter from the `notebook` directory so the existing relative data paths resolve correctly.

Run:

```text
01_eda.ipynb
02_churn_classification.ipynb
03_customer_segmentation.ipynb
```

The classification and segmentation notebooks create their output CSV files automatically.

### 4. Open the dashboard

Open `Retail_Churn_Dashboard.pbix` in Power BI Desktop.

Update its data-source paths to your local files before refreshing the report.

## Limitations and next steps

The current project establishes a working analysis and modeling workflow. The main improvements still needed are:

- Evaluate across multiple historical cutoff dates.
- Use a separate validation set for model and threshold selection.
- Check probability calibration before treating risk scores as reliable probabilities.
- Standardize country values, including trailing whitespace.
- Review unusual purchase totals and reconcile cancellations where possible.
- Add a pinned dependency file for reproducibility.
- Evaluate retention actions through an experiment before claiming reduced churn or increased revenue.

The data represents one retailer during a historical period. Results should be interpreted within that setting.

## Data credit

Chen, D. (2012). *Online Retail II*. UCI Machine Learning Repository.

https://doi.org/10.24432/C5CG6D