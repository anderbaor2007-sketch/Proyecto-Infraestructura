import argparse
import json
import random
import time

import boto3


def argumentos():
    analizador = argparse.ArgumentParser()
    analizador.add_argument("--endpoint", required=True)
    analizador.add_argument("--region", default="us-east-2")
    analizador.add_argument("--equipo-id", required=True)
    analizador.add_argument("--empresa-id", required=True)
    analizador.add_argument("--latitud", type=float, default=-8.1116)
    analizador.add_argument("--longitud", type=float, default=-79.0288)
    analizador.add_argument("--intervalo", type=float, default=10.0)
    analizador.add_argument("--eventos", type=int, default=0)
    analizador.add_argument("--paso", type=float, default=0.0004)
    return analizador.parse_args()


def evento(args, latitud, longitud):
    velocidad = round(random.uniform(0, 25), 1)
    return {
        "equipoId": args.equipo_id,
        "empresaId": args.empresa_id,
        "latitud": round(latitud, 6),
        "longitud": round(longitud, 6),
        "velocidad": velocidad,
        "motor": "encendido" if velocidad > 0 else "apagado",
        "timestamp": int(time.time() * 1000),
    }


def main():
    args = argumentos()
    cliente = boto3.client("iot-data", region_name=args.region, endpoint_url=f"https://{args.endpoint}")
    topico = f"terrafleet/equipos/{args.equipo_id}/telemetria"
    latitud, longitud = args.latitud, args.longitud
    enviados = 0
    while args.eventos == 0 or enviados < args.eventos:
        latitud += random.uniform(-args.paso, args.paso)
        longitud += random.uniform(-args.paso, args.paso)
        mensaje = evento(args, latitud, longitud)
        cliente.publish(topic=topico, qos=1, payload=json.dumps(mensaje))
        enviados += 1
        print(json.dumps(mensaje), flush=True)
        time.sleep(args.intervalo)


if __name__ == "__main__":
    main()
