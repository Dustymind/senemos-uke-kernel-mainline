// SPDX-License-Identifier: GPL-2.0-only
#include <linux/bootconfig.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/string.h>

/*
 * The OEM DTB leaves the pogo keyboard bus disabled and describes its pins
 * with vendor *_pin cells only. Enable the bus and publish the generic
 * bindings the mainline Nanosic 803 driver consumes.
 *
 * Both nodes come from the OEM graph, so the pin numbers are Uke's own and
 * not copied from another board. arch_initcall runs before
 * of_platform_default_populate_init(), which is when the geni platform device
 * is created and its availability is sampled.
 */
#ifdef CONFIG_BOOT_CONFIG
#define UKE_KBD_GPIO_COUNT 4
static __be32 uke_kbd_gpio_cells[UKE_KBD_GPIO_COUNT][3];
/* irq is active low in the OEM cell flags (0x2001); the rest are active high. */
static const u32 uke_kbd_pins[UKE_KBD_GPIO_COUNT] = { 116, 127, 98, 128 };
static const u32 uke_kbd_flags[UKE_KBD_GPIO_COUNT] = { 1, 0, 0, 0 };
static struct property uke_kbd_gpio_props[UKE_KBD_GPIO_COUNT] = {
	{ .name = "irq-gpios", .length = sizeof(uke_kbd_gpio_cells[0]),
	  .value = uke_kbd_gpio_cells[0] },
	{ .name = "reset-gpios", .length = sizeof(uke_kbd_gpio_cells[1]),
	  .value = uke_kbd_gpio_cells[1] },
	{ .name = "sleep-gpios", .length = sizeof(uke_kbd_gpio_cells[2]),
	  .value = uke_kbd_gpio_cells[2] },
	{ .name = "vdd-gpios", .length = sizeof(uke_kbd_gpio_cells[3]),
	  .value = uke_kbd_gpio_cells[3] },
};
static char uke_bus_status[] = "okay";
static struct property uke_bus_status_prop = {
	.name = "status", .length = sizeof(uke_bus_status), .value = uke_bus_status,
};
static char uke_bus_compatible[] = "qcom,geni-i2c";
static struct property uke_bus_compatible_prop = {
	.name = "compatible", .length = sizeof(uke_bus_compatible),
	.value = uke_bus_compatible,
};
/* Mainline geni i2c reads clock-frequency; the OEM node only has clk-freq-out. */
static __be32 uke_bus_clock_frequency[] = { cpu_to_be32(400000) };
static struct property uke_bus_clock_frequency_prop = {
	.name = "clock-frequency", .length = sizeof(uke_bus_clock_frequency),
	.value = uke_bus_clock_frequency,
};
/*
 * The driver refuses to create the touchpad input device without these two.
 * Derive them from the OEM edge-area maxima instead of copying another board's
 * numbers: the edge limits share the coordinate space with the reports.
 */
static __be32 uke_kbd_resolution_x[1], uke_kbd_resolution_y[1];
static struct property uke_kbd_resolution_x_prop = {
	.name = "touchpad-resolution-x", .length = sizeof(uke_kbd_resolution_x),
	.value = uke_kbd_resolution_x,
};
static struct property uke_kbd_resolution_y_prop = {
	.name = "touchpad-resolution-y", .length = sizeof(uke_kbd_resolution_y),
	.value = uke_kbd_resolution_y,
};

static int __init uke_keyboard_bus(void)
{
	static const char bus_path[] =
		"/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000";
	static const char kbd_path[] =
		"/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000/nanosic@4c";
	struct device_node *tlmm, *bus, *kbd;
	unsigned int i;
	u32 max;
	int ret;

	tlmm = of_find_node_by_path("/soc/pinctrl@f000000");
	if (!tlmm)
		return 0;
	bus = of_find_node_by_path(bus_path);
	kbd = of_find_node_by_path(kbd_path);
	if (!bus || !kbd) {
		ret = 0;
		goto out;
	}
	for (i = 0; i < UKE_KBD_GPIO_COUNT; i++) {
		__be32 *cells = uke_kbd_gpio_props[i].value;

		cells[0] = cpu_to_be32(tlmm->phandle);
		cells[1] = cpu_to_be32(uke_kbd_pins[i]);
		cells[2] = cpu_to_be32(uke_kbd_flags[i]);
	}
	ret = of_update_property(bus, &uke_bus_status_prop);
	if (!ret)
		ret = of_update_property(bus, &uke_bus_compatible_prop);
	if (!ret)
		ret = of_update_property(bus, &uke_bus_clock_frequency_prop);
	for (i = 0; !ret && i < UKE_KBD_GPIO_COUNT; i++)
		ret = of_update_property(kbd, &uke_kbd_gpio_props[i]);
	if (!ret && !of_property_read_u32(kbd, "touchpad,edge-area-right-max",
					 &max)) {
		uke_kbd_resolution_x[0] = cpu_to_be32(max + 1);
		ret = of_update_property(kbd, &uke_kbd_resolution_x_prop);
	}
	if (!ret && !of_property_read_u32(kbd, "touchpad,edge-area-bottom-max",
					 &max)) {
		uke_kbd_resolution_y[0] = cpu_to_be32(max + 1);
		ret = of_update_property(kbd, &uke_kbd_resolution_y_prop);
	}
out:
	of_node_put(kbd);
	of_node_put(bus);
	of_node_put(tlmm);
	return ret;
}
#endif /* CONFIG_BOOT_CONFIG */

static int __init uke_identity_init(void)
{
#ifdef CONFIG_BOOT_CONFIG
	struct xbc_node *hardware_node = NULL, *product_node = NULL;
	struct device_node *root;
	const char *hardware, *product;
	static char model[] = "POCO Pad X1";
	static struct property property = {
		.name = "model", .length = sizeof(model), .value = model,
	};
	static struct {
		const char *path;
		struct property property;
	} updates[] = {
#define UKE_IDENTITY(p, n, v) { p, { .name = n, .length = sizeof(v), .value = v } }
		UKE_IDENTITY("/firmware/uke-accessories", "pen-model", "POCO Focus Pen"),
		UKE_IDENTITY("/firmware/uke-accessories", "keyboard-model", "POCO Focus Keyboard"),
		UKE_IDENTITY("/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000/nanosic@4c", "model", "POCO Focus Keyboard"),
		UKE_IDENTITY("/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0", "label", "POCO Pad X1 Touchscreen"),
		UKE_IDENTITY("/soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000/ntag@57", "status", "okay"),
#undef UKE_IDENTITY
	};
	unsigned int i;
	int ret;

	if (!of_machine_is_compatible("xiaomi,uke") ||
	    !of_machine_is_compatible("qcom,sm7675"))
		return 0;
	hardware = xbc_find_value("androidboot.hardware.sku", &hardware_node);
	product = xbc_find_value("androidboot.product.hardware.sku", &product_node);
	/* Accept only the exact scalar SKU observed in stock and Fedora boot data. */
	if ((!hardware && !product) ||
	    (hardware && (!hardware_node || xbc_node_is_array(hardware_node) ||
			 strcmp(hardware, "ukepgl"))) ||
	    (product && (!product_node || xbc_node_is_array(product_node) ||
			strcmp(product, "ukepgl"))))
		return 0;
	root = of_find_node_by_path("/");
	if (!root)
		return -ENODEV;
	/* OF retains the property, so neither it nor its value may be init data. */
	ret = of_update_property(root, &property);
	of_node_put(root);
	if (ret)
		return ret;
	for (i = 0; i < sizeof(updates) / sizeof(updates[0]); i++) {
		root = of_find_node_by_path(updates[i].path);
		if (!root)
			continue;
		ret = of_update_property(root, &updates[i].property);
		of_node_put(root);
		if (ret)
			return ret;
	}
	return uke_keyboard_bus();
#else
	return 0;
#endif
}
/* XBC exists until all initcalls finish; update OF before userspace starts. */
arch_initcall(uke_identity_init);
