"""
Alerts Router - Placeholder for future implementation
"""
from fastapi import APIRouter

router = APIRouter(tags=["Alerts"])


@router.get("/")
def list_alerts():
    """
    List alerts - To be implemented.
    
    Future functionality:
    - Query alerts from MongoDB
    - Filter by device, severity, date range
    - Mark alerts as resolved
    """
    return {
        "message": "Alerts endpoint placeholder",
        "status": "not_implemented",
        "future_features": [
            "List alerts by device",
            "Filter by severity",
            "Mark as resolved",
            "Alert history"
        ]
    }
