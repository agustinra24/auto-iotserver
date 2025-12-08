"""
Router de Alertas - Placeholder para implementación futura
"""
from fastapi import APIRouter

router = APIRouter(tags=["Alerts"])


@router.get("/")
def list_alerts():
    """
    Listar alertas - Por implementar.
    
    Funcionalidad futura:
    - Consultar alertas de MongoDB
    - Filtrar por dispositivo, severidad, rango de fechas
    - Marcar alertas como resueltas
    """
    return {
        "message": "Placeholder de endpoint de alertas",
        "status": "no_implementado",
        "future_features": [
            "Listar alertas por dispositivo",
            "Filtrar por severidad",
            "Marcar como resuelta",
            "Historial de alertas"
        ]
    }
