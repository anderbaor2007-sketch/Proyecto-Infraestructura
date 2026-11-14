const cfg = window.TERRAFLEET;
const estado = { token: sessionStorage.getItem("token"), vista: "catalogo" };

function el(etiqueta, atributos = {}, ...hijos) {
  const nodo = document.createElement(etiqueta);
  for (const [clave, valor] of Object.entries(atributos)) {
    if (clave.startsWith("on")) {
      nodo.addEventListener(clave.slice(2), valor);
    } else {
      nodo.setAttribute(clave, valor);
    }
  }
  nodo.append(...hijos);
  return nodo;
}

function campo(nombre, etiqueta, tipo = "text", extra = {}) {
  return el("label", {}, etiqueta, el("input", { name: nombre, type: tipo, ...extra }));
}

function datosFormulario(formulario) {
  return Object.fromEntries(new FormData(formulario).entries());
}

function aviso(mensaje, tipo = "ok") {
  const nodo = document.getElementById("aviso");
  nodo.hidden = !mensaje;
  nodo.className = tipo;
  nodo.textContent = mensaje || "";
}

async function intentar(accion) {
  try {
    aviso("");
    await accion();
  } catch (error) {
    aviso(error.message, "error");
  }
}

async function cognito(operacion, cuerpo) {
  const respuesta = await fetch(cfg.cognitoUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": `AWSCognitoIdentityProviderService.${operacion}`,
    },
    body: JSON.stringify({ ClientId: cfg.clienteId, ...cuerpo }),
  });
  const datos = await respuesta.json();
  if (!respuesta.ok) {
    throw new Error(datos.message || datos.__type);
  }
  return datos;
}

async function api(ruta, opciones = {}) {
  const respuesta = await fetch(ruta, {
    ...opciones,
    headers: { "Content-Type": "application/json", Authorization: estado.token },
  });
  const datos = await respuesta.json().catch(() => ({}));
  if (respuesta.status === 401) {
    cerrarSesion();
    throw new Error("La sesión expiró, inicia sesión nuevamente");
  }
  if (!respuesta.ok) {
    throw new Error(datos.mensaje || datos.message || `Error ${respuesta.status}`);
  }
  return datos;
}

function perfil() {
  const carga = estado.token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  const datos = JSON.parse(atob(carga));
  const grupos = datos["cognito:groups"] || [];
  return { correo: datos.email, grupos, esEmpresa: grupos.includes("empresas") || grupos.includes("administradores") };
}

function cerrarSesion() {
  sessionStorage.removeItem("token");
  estado.token = null;
  dibujar();
}

function vistaAcceso() {
  const entrar = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = datosFormulario(evento.target);
          const resultado = await cognito("InitiateAuth", {
            AuthFlow: "USER_PASSWORD_AUTH",
            AuthParameters: { USERNAME: datos.correo, PASSWORD: datos.clave },
          });
          estado.token = resultado.AuthenticationResult.IdToken;
          sessionStorage.setItem("token", estado.token);
          dibujar();
        });
      },
    },
    campo("correo", "Correo", "email", { required: "" }),
    campo("clave", "Contraseña", "password", { required: "" }),
    el("button", {}, "Ingresar")
  );

  const registrar = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = datosFormulario(evento.target);
          await cognito("SignUp", {
            Username: datos.correo,
            Password: datos.clave,
            UserAttributes: [{ Name: "email", Value: datos.correo }],
          });
          aviso("Revisa tu correo e ingresa el código en la sección de confirmación");
        });
      },
    },
    campo("correo", "Correo", "email", { required: "" }),
    campo("clave", "Contraseña (mínimo 10, mayúscula, minúscula y número)", "password", { required: "", minlength: "10" }),
    el("button", { class: "secundario" }, "Crear cuenta")
  );

  const confirmar = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = datosFormulario(evento.target);
          await cognito("ConfirmSignUp", { Username: datos.correo, ConfirmationCode: datos.codigo });
          aviso("Cuenta confirmada, ya puedes ingresar");
        });
      },
    },
    campo("correo", "Correo", "email", { required: "" }),
    campo("codigo", "Código recibido", "text", { required: "" }),
    el("button", { class: "secundario" }, "Confirmar")
  );

  return el(
    "div",
    {},
    el("section", {}, el("h2", {}, "Ingresar"), entrar),
    el("section", {}, el("h2", {}, "Crear cuenta"), registrar),
    el("section", {}, el("h2", {}, "Confirmar cuenta"), confirmar)
  );
}

function tarjetaEquipo(equipo) {
  const salida = el("div", {});
  const formulario = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = datosFormulario(evento.target);
          const reserva = await api("/reservas", {
            method: "POST",
            body: JSON.stringify({ equipoId: equipo.id, fechaInicio: datos.inicio, fechaFin: datos.fin }),
          });
          aviso(`Reserva ${reserva.reservaId} registrada como pendiente. Total: S/ ${reserva.total.toFixed(2)}`);
        });
      },
    },
    campo("inicio", "Desde", "date", { required: "" }),
    campo("fin", "Hasta", "date", { required: "" }),
    el("button", {}, "Reservar"),
    el(
      "button",
      {
        type: "button",
        class: "secundario",
        onclick: () =>
          intentar(async () => {
            const datos = datosFormulario(formulario);
            const consulta = new URLSearchParams();
            if (datos.inicio) consulta.set("desde", datos.inicio);
            if (datos.fin) consulta.set("hasta", datos.fin);
            const resultado = await api(`/disponibilidad/${equipo.id}?${consulta}`);
            salida.textContent = `${resultado.libres.length} días libres, ${resultado.ocupadas.length} tramos ocupados`;
          }),
      },
      "Ver fechas"
    )
  );
  return el(
    "article",
    {},
    equipo.fotoUrl ? el("img", { src: equipo.fotoUrl, alt: equipo.nombre }) : el("div", {}),
    el("h3", {}, equipo.nombre),
    el("p", {}, `${equipo.marca} ${equipo.modelo || ""} · ${equipo.categoria} · ${equipo.ciudad}`),
    el("p", {}, `S/ ${equipo.tarifaDia.toFixed(2)} por día`),
    el("small", {}, equipo.id),
    formulario,
    salida
  );
}

function vistaCatalogo() {
  const resultados = el("div", { class: "rejilla" });
  const filtros = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const consulta = new URLSearchParams();
          for (const [clave, valor] of Object.entries(datosFormulario(evento.target))) {
            if (valor) consulta.set(clave, valor);
          }
          const datos = await api(`/equipos?${consulta}`);
          resultados.replaceChildren(...datos.equipos.map(tarjetaEquipo));
          if (datos.equipos.length === 0) aviso("No hay equipos con esos filtros");
        });
      },
    },
    campo("ciudad", "Ciudad"),
    campo("categoria", "Categoría"),
    campo("marca", "Marca"),
    campo("tarifaMax", "Tarifa máxima", "number", { min: "0", step: "0.01" }),
    el("button", {}, "Buscar")
  );
  return el("div", {}, el("section", {}, filtros), resultados);
}

function vistaPublicar() {
  const publicar = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = datosFormulario(evento.target);
          const cuerpo = {
            nombre: datos.nombre,
            categoria: datos.categoria,
            marca: datos.marca,
            modelo: datos.modelo || undefined,
            ciudad: datos.ciudad,
            tarifaDia: Number(datos.tarifaDia),
          };
          if (datos.latitud && datos.longitud && datos.radioKm) {
            cuerpo.geocerca = {
              latitud: Number(datos.latitud),
              longitud: Number(datos.longitud),
              radioKm: Number(datos.radioKm),
            };
          }
          const creado = await api("/equipos", { method: "POST", body: JSON.stringify(cuerpo) });
          aviso(`Equipo publicado con id ${creado.equipoId}`);
        });
      },
    },
    campo("nombre", "Nombre", "text", { required: "" }),
    campo("categoria", "Categoría", "text", { required: "" }),
    campo("marca", "Marca", "text", { required: "" }),
    campo("modelo", "Modelo"),
    campo("ciudad", "Ciudad", "text", { required: "" }),
    campo("tarifaDia", "Tarifa por día (S/)", "number", { required: "", min: "0.01", step: "0.01" }),
    campo("latitud", "Geocerca: latitud", "number", { step: "any" }),
    campo("longitud", "Geocerca: longitud", "number", { step: "any" }),
    campo("radioKm", "Geocerca: radio (km)", "number", { step: "any", min: "0.01" }),
    el("button", {}, "Publicar")
  );

  const foto = el(
    "form",
    {
      onsubmit: (evento) => {
        evento.preventDefault();
        intentar(async () => {
          const datos = new FormData(evento.target);
          const archivo = datos.get("archivo");
          const autorizacion = await api(`/equipos/${datos.get("equipoId")}/foto`, {
            method: "POST",
            body: JSON.stringify({ contentType: archivo.type }),
          });
          const envio = new FormData();
          for (const [clave, valor] of Object.entries(autorizacion.campos)) envio.append(clave, valor);
          envio.append("file", archivo);
          const subida = await fetch(autorizacion.url, { method: "POST", body: envio });
          if (!subida.ok) throw new Error("No se pudo subir la fotografía, solicita una nueva autorización");
          aviso("Fotografía cargada");
        });
      },
    },
    campo("equipoId", "Id del equipo", "text", { required: "" }),
    campo("archivo", "Fotografía (JPEG o PNG, hasta 1 MB)", "file", { required: "", accept: "image/jpeg,image/png" }),
    el("button", { class: "secundario" }, "Subir")
  );

  return el(
    "div",
    {},
    el("section", {}, el("h2", {}, "Publicar equipo"), publicar),
    el("section", {}, el("h2", {}, "Cargar fotografía"), foto)
  );
}

function vistaTelemetria() {
  const salida = el("div", {});
  const consulta = el(
    "form",
    {
      onsubmit: (evento) => evento.preventDefault(),
    },
    campo("equipoId", "Id del equipo", "text", { required: "" }),
    el(
      "button",
      {
        type: "button",
        onclick: () =>
          intentar(async () => {
            const { equipoId } = datosFormulario(consulta);
            const p = await api(`/telemetria/${equipoId}/ultima`);
            const enlace = `https://www.openstreetmap.org/?mlat=${p.latitud}&mlon=${p.longitud}#map=16/${p.latitud}/${p.longitud}`;
            salida.replaceChildren(
              el("p", {}, `Posición: ${p.latitud}, ${p.longitud} · ${p.velocidad} km/h · motor ${p.motor}`),
              el("p", {}, `Último evento: ${new Date(p.timestamp).toLocaleString()}${p.fueraGeocerca ? " · fuera de la geocerca" : ""}`),
              el("a", { href: enlace, target: "_blank", rel: "noopener" }, "Ver en el mapa")
            );
          }),
      },
      "Última posición"
    ),
    el(
      "button",
      {
        type: "button",
        class: "secundario",
        onclick: () =>
          intentar(async () => {
            const { equipoId } = datosFormulario(consulta);
            const r = await api(`/telemetria/${equipoId}/ruta`);
            const filas = r.puntos.slice(-20).map((p) =>
              el("tr", {}, el("td", {}, new Date(p.timestamp).toLocaleTimeString()), el("td", {}, String(p.latitud)), el("td", {}, String(p.longitud)), el("td", {}, String(p.velocidad)))
            );
            salida.replaceChildren(
              el("p", {}, `${r.puntos.length} puntos en las últimas 24 horas (últimos 20)`),
              el("table", {}, el("tr", {}, el("th", {}, "Hora"), el("th", {}, "Latitud"), el("th", {}, "Longitud"), el("th", {}, "Km/h")), ...filas)
            );
          }),
      },
      "Recorrido 24 h"
    )
  );
  return el("section", {}, el("h2", {}, "Telemetría de flota"), consulta, salida);
}

function vistaPrincipal() {
  const datos = perfil();
  const vistas = { catalogo: vistaCatalogo, telemetria: vistaTelemetria };
  if (datos.esEmpresa) vistas.publicar = vistaPublicar;
  const etiquetas = { catalogo: "Catálogo", publicar: "Publicar", telemetria: "Telemetría" };
  if (!vistas[estado.vista]) estado.vista = "catalogo";

  const menu = el(
    "nav",
    {},
    ...Object.keys(vistas).map((clave) =>
      el(
        "button",
        {
          class: clave === estado.vista ? "activo" : "",
          onclick: () => {
            estado.vista = clave;
            aviso("");
            dibujar();
          },
        },
        etiquetas[clave]
      )
    )
  );
  return el("div", {}, menu, vistas[estado.vista]());
}

function dibujar() {
  const sesion = document.getElementById("sesion");
  const contenido = document.getElementById("contenido");
  if (!estado.token) {
    sesion.replaceChildren();
    contenido.replaceChildren(vistaAcceso());
    return;
  }
  sesion.replaceChildren(
    el("span", {}, `${perfil().correo} `),
    el("button", { class: "secundario", onclick: cerrarSesion }, "Salir")
  );
  contenido.replaceChildren(vistaPrincipal());
}

dibujar();
